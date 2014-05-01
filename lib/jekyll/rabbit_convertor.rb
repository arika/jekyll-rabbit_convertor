# encoding: utf-8
require 'jekyll/rabbit_convertor/version'
require 'jekyll/rabbit_convertor/rabbit_ext'
require 'erb'


module Jekyll
  class RabbitConverter < Jekyll::Converter
    priority :low
    safe false

    DEFAULT_SLIDE_HTML_TEMPLATE = 'bootstrap_carousel.html.erb'
    DEFAULT_SLIDE_IMAGE_WIDTH = 640
    DEFAULT_SLIDE_IMAGE_HEIGHT = 480

    class Template
      include ERB::Util

      def initialize(src)
        @erb = ERB.new(src)
      end

      def render(digest, images)
        @erb.result(binding)
      end
    end

    def matches(ext)
      /\A\.rab\z/i =~ ext
    end

    def output_ext(ext)
      '.html'
    end

    def convert(content)
      content = content.strip

      output_dir = @config['destination'].sub(%r!/+\z!, '')
      output_dir_patt = %r!\A#{Regexp.quote(output_dir)}/!
      rabbit_dir = 'rabbit-image'

      digest = Digest::MD5.hexdigest(content)
      @converted ||= {}
      return @converted[digest] if @converted[digest]

      image_filename_base = File.join(
        output_dir,
        rabbit_dir, digest, 'slide')
      image_basedir = File.dirname(image_filename_base)

      # 生成したスライド画像がディレクトリごと
      # Jekyll::Site::Cleanerに消されるのを回避する
      ["#{rabbit_dir}$", "#{rabbit_dir}/#{digest}$"].each do |f|
        add_keep_files(f)
      end

      unless File.exist?(image_basedir)
        FileUtils.mkdir_p(image_basedir)
        Jekyll.logger.debug('Rabbit:', "created slide image directory #{image_basedir.inspect}")
      end

      image_width = slide_image_width
      image_height = slide_image_height

      args = [
        '-s',
        '-S', "#{image_width},#{image_height}",
        '-b', image_filename_base,
        '--output-html',
        '--logger', 'jekyll',
        '--log-level', Rabbit::Logger::JEKYLL::LOG_LEVEL[Jekyll.logger.log_level],
        '-T', 'stringobject', content,
      ]
      Jekyll.logger.debug('Rabbit:', "rendering #{args.inspect}")

      th = Thread.start do # 生成したHTMLを受け取る方法がないので苦肉の策
        Thread.current[:exception] = nil
        Thread.current[:result] = ''
        Thread.current[:images] = {}
        Thread.current[:titles] = {}
        begin
          Rabbit::Command::Rabbit.run(*args)
        rescue
          Thread.current[:exception] = $!
        end
      end.join

      raise th[:exception] if th[:exception]

      Jekyll.logger.debug('Rabbit:', "generated html text #{th[:result].inspect}")

      title_image = nil
      images = []
      th[:images].each do |slide_number, image_filename|
        f = image_filename.sub(output_dir_patt, '')
        Jekyll.logger.debug('Rabbit:', "image generated \##{slide_number} #{th[:titles][slide_number]} as #{f}")

        image_url = "/#{f}"
        images << [
          slide_number, th[:titles][slide_number],
          image_url, image_width, image_height,
        ]
        title_image = image_url if slide_number == 0

        # 生成したスライド画像が
        # Jekyll::Site::Cleanerに消されるのを回避する
        add_keep_files(f)
      end

      html = render_slide_html(digest, images)
      @converted[digest] = <<-EOH
<!-- begin rabbit-content #{digest} -->
<!-- meta
title #{th[:titles][0]}
image #{title_image}
width #{image_width}
height #{image_height}
-->
<!-- begin slide -->
#{html.chomp}
<!-- end slide -->
<!-- begin text -->
#{th[:result].chomp}
<!-- end text -->
<!-- end rabbit-content #{digest} -->
      EOH
    end

    # 文字列からRabbitConverterで生成した部分を抽出する。
    def self.extract_html(str)
      str.scan(/^<!-- begin rabbit-content ([\da-f]{32}) -->\n(.*?)\n<!-- end rabbit-content \1 -->\n/m).
        map {|digest, content| content }
    end

    # extract_htmlで抽出した文字列の中から
    # メタ情報を抽出してハッシュで返す。
    def self.extract_meta(str)
      meta = {}
      str.scan(/^<!-- meta\n(.*?)\n-->\n/m) do
        $1.scan(/^(\S+)[ \t]+(.*)$/) do
          meta[$1] = $2
        end
      end
      meta
    end

    # extract_htmlで抽出した文字列の中から
    # スライド画像を抽出する。
    def self.extract_slide(str)
      if /^<!-- begin slide -->\n(.*?)\n<!-- end slide -->\n/m =~ str
        $1
      else
        nil
      end
    end

    private

    def slide_image_width
      (@config['rabbit'] || {})['width'] || DEFAULT_SLIDE_IMAGE_WIDTH
    end

    def slide_image_height
      (@config['rabbit'] || {})['height'] || DEFAULT_SLIDE_IMAGE_HEIGHT
    end

    def slide_html_template
      erb_name = (@config['rabbit'] || {})['template'] || DEFAULT_SLIDE_HTML_TEMPLATE
      template_dir = File.expand_path( '../rabbit_convertor/templates', __FILE__)
      File.join(template_dir, erb_name)
    end

    def render_slide_html(digest, images)
      t = Template.new(File.read(slide_html_template))
      t.render(digest, images)
    end

    def add_keep_files(str)
      unless @config['keep_files'].include?(str)
        @config['keep_files'] << str
      end
    end
  end # class RabbitConverter

  module Filters
    # 与えられたテキストがRabbitスライドから
    # 生成されたものであった場合、
    # スライド画像部分を抽出して返す。
    # 与えられたテキストがRabbitスライドでなければ
    # そのまま返す。
    def rabbit_slide(input)
      html = RabbitConverter.extract_html(input).first
      return input unless html

      meta = RabbitConverter.extract_meta(html)
      return input if meta.empty?

      slide = RabbitConverter.extract_slide(html)
      return input unless slide

      slide
    end

    # 与えられたテキストがRabbitスライドから
    # 生成されたものであった場合、
    # タイトルスライド画像と記事へのリンクを返す。(テキストリンク付き)
    # 与えられたテキストがRabbitスライドでなければ
    # そのまま返す。
    def rabbit_title_slide_with_text_link(input, url)
      rabbit_title_slide(input, url, true)
    end

    # 与えられたテキストがRabbitスライドから
    # 生成されたものであった場合、
    # タイトルスライド画像と記事へのリンクを返す。
    # 与えられたテキストがRabbitスライドでなければ
    # そのまま返す。
    def rabbit_title_slide(input, url, with_text_link = false)
      html = RabbitConverter.extract_html(input).first
      return input unless html

      meta = RabbitConverter.extract_meta(html)
      return input if meta.empty?

      escaped_url = xml_escape(url)
      escaped_title = xml_escape(meta['title'])

      html = <<-EOH
<a href='#{escaped_url}'><img
  src='#{xml_escape meta['image']}'
  title='#{escaped_title}'
  alt='#{escaped_title}'
  width='#{xml_escape meta['width']}'
  height='#{xml_escape meta['height']}'></a>
      EOH

      html << <<-EOH if with_text_link
<br />
<a href='#{escaped_url}'>#{escaped_title}</a>
      EOH

      html
    end
  end
end # module Jekyll
