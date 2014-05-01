require 'rabbit/command/rabbit'
require 'rabbit/parser/rd'
require 'rabbit/html/generator'
require 'rabbit/source'
require 'rabbit/logger'
require 'digest/md5'
require 'fileutils'

module Rabbit
  module Source
    class StringObject < Memory
      def self.initial_args_description
        '[RD-text]'
      end

      def initialize(encoding, logger, text)
        super(encoding, logger)
        @original_source = text
        reset
      end
    end
  end # module Source

  module Logger
    # Rabbitのロガーから
    # Jekyllのロガーに受け渡す
    class JEKYLL
      include Base

      # Jekyllのログレベルを
      # Rabbitのログレベルに変換する
      LOG_LEVEL = {
        Jekyll::Stevenson::DEBUG => 'debug',
        Jekyll::Stevenson::INFO => 'info',
        Jekyll::Stevenson::WARN => 'wawrn',
        Jekyll::Stevenson::ERROR => 'error',
      }

      # Rabbitのログレベルを
      # Jekyllのログメソッドに変換する
      LOG_METHOD = {
        Severity::DEBUG => :debug,
        Severity::INFO => :info,
        Severity::WARNING => :warn,
        Severity::ERROR => :error,
        Severity::FATAL => :error,
        Severity::UNKNOWN => :error,
      }

      def do_log(severity, prog_name, message)
        m = LOG_METHOD[severity]
        topic = "#{prog_name || 'Rabbit'}:"

        # Rabbitのログの一部は複数行を前提としているが
        # Jekyllのロガーは改行文字を削除してしまうため
        # あえて複数回に分けてログ出力する
        message.each_line do |l|
          Jekyll.logger.__send__(m, topic, l)
        end
      end
    end
  end # module Logger

  module Parser
    class RD
      # RabbitのRDにコメント機能を追加する
      #
      #   = タイトル
      #
      #   == comment
      #
      #   ここに書いたものはスライドには表示されないが
      #   HTMLには出力される。
      module CommentExtension
        class Comment < Rabbit::Parser::NoteSetter
          def initialize(slide)
            @slide = slide
          end
          def apply(element)
            @slide['comment'] ||= []
            @slide['comment'] << element
          end
        end

        def apply_to_Headline(element, title)
          unless element.level == 2 &&
              /\Acomment\z/i =~ title.first.text
            return super
          end
          Comment.new(@slides.last)
        end
      end # module CommentExtension

      class RD2RabbitVisitor
        prepend CommentExtension
      end
    end # class RD
  end # module Parser

  # 生成されるHTMLにスライドにあった
  # 強調その他の装飾を残す。
  module Element
    {
      Keyword => {span: {class: :keyword}},
      Comment => {span: {class: :comment}},
      Emphasis => {em: {class: :emphasis}},
      Code => {code: {class: :code}},
      Variable => {var: {}},
      Keyboard => {code: {class: :keyboard}},
      Index => {em: {class: :index}},
      Note => {span: {class: :note}},
      Verbatim => {tt: {}},
      DeletedText => {del: {}},
      Subscript => {sub: {}},
      Superscript => {sup: {}},
    }.each do |cls, tags|
      cls.class_eval do
        ot = tags.inject('') do |tag, (name, attrs)|
          tag << if attrs.empty?
              "<#{name}>"
            else
              %Q!<#{name} #{attrs.map {|k, v| "#{k}='#{ERB::Util.h(v.to_s)}'" }.join(' ')}>!
            end
        end
        ct = tags.inject('') do |tag, (name, attrs)|
          tag = "#{tag}</#{name}>"
        end
        define_method(:to_html) do |generator|
          "#{ot}#{super(generator)}#{ct}"
        end
      end
    end

    class ReferText
      def to_html(generator)
        html_id = generator.html_labels[to]
        href = html_id ? "\##{html_id}" : to
        "<a href='#{generator.h(href)}'>#{super}</a>"
      end
    end
  end # module Element

  module HTML
    module CommentExtension
      attr_accessor :html_labels

      def save
        @html_labels = {}
        digest = Digest::MD5.hexdigest(@canvas.source)

        # RD内の参照を限定的にサポートする
        # 参照をページ単位のリンクに展開できるようにする
        # (スライド内で使うのではなく
        # commentブロックで特定のページを参照するのに使うため)
        @canvas.slides.each_with_index do |slide, slide_number|
          html_id = "slide-#{slide_number}-#{digest}"
          @html_labels[slide_number] = html_id
          slide.elements.each do |element|
            next unless element.is_a?(Element::HeadLine)
            @html_labels[element.text] = html_id
          end
        end

        super
      end

      def save_html(slide, slide_number)
        super # スライドイメージが生成される

        html = ''
        # スライド本文に対応するHTMLを生成する
        html << "<div class='slide-and-comment' id='#{h @html_labels[slide_number]}'>"
        html << slide.to_html(self).gsub(%r!</?span[^>]*>!, '') # フォント指定を除去する

        # commentブロックに対応するHMLTを生成する
        if slide['comment']
          div_class = h('slide-comment')
          div_class << h(' title-slide-comment') if slide.is_a?(Element::TitleSlide)
          html << "<div class='#{div_class}'>"
          slide['comment'].each do |element|
            html << element.to_html(self)
          end
          html << '</div>'
        end

        html << '</div>'

        # 生成したHTMLをJekyllに渡す
        Thread.current[:images][slide_number] = image_filename(slide_number)
        Thread.current[:titles][slide_number] = slide.title
        Thread.current[:result] << html
      end

      def output_html(*args)
        # noop
      end
    end # class Generator

    class Generator
      prepend CommentExtension
    end
  end # module HTML
end # module Rabbit
