require "simple_hashtag/hashtag"
require "simple_hashtag/hashtag_list"
require "simple_hashtag/hashtag_list_parser"
require "simple_hashtag/hashtagging"
require "simple_hashtag/hashtaggable"

module SimpleHashtag

  def self.setup
    @configuration ||= Configuration.new
    yield @configuration if block_given?
  end

  def self.method_missing(method_name, *args, &block)
    @configuration.respond_to?(method_name) ?
        @configuration.send(method_name, *args, &block) : super
  end

  def self.respond_to?(method_name, include_private=false)
    @configuration.respond_to? method_name
  end

  def self.glue
    setting = ','
    delimiter = setting.kind_of?(Array) ? setting[0] : setting
    delimiter.ends_with?(' ') ? delimiter : "#{delimiter} "
  end

  class Configuration
    attr_accessor :delimiter, :force_lowercase, :force_parameterize,
                  :strict_case_match, :remove_unused_tags

    def initialize
      @delimiter = ','
      @force_lowercase = false
      @force_parameterize = false
      @strict_case_match = false
      @remove_unused_tags = false
    end
  end

  setup
end
