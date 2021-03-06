module SimpleHashtag
  class TagList < Array
    attr_accessor :owner

    def initialize(*args)
      add(*args)
    end

    ##
    # Add tags to the tag_list. Duplicate or blank tags will be ignored.
    # Use the <tt>:parse</tt> option to add an unparsed tag string.
    #
    # Example:
    #   tag_list.add("Fun", "Happy")
    #   tag_list.add("Fun, Happy", :parse => true)
    def add(*names)
      extract_and_apply_options!(names)
      concat(names)
      clean!
      self
    end

    # Append---Add the tag to the tag_list. This
    # expression returns the tag_list itself, so several appends
    # may be chained together.
    def <<(obj)
      add(obj)
    end

    # Concatenation --- Returns a new tag list built by concatenating the
    # two tag lists together to produce a third tag list.
    def +(other_tag_list)
      TagList.new.add(self).add(other_tag_list)
    end

    # Appends the elements of +other_tag_list+ to +self+.
    def concat(other_tag_list)
      super(other_tag_list).send(:clean!)
    end

    ##
    # Remove specific tags from the tag_list.
    # Use the <tt>:parse</tt> option to add an unparsed tag string.
    #
    # Example:
    #   tag_list.remove("Sad", "Lonely")
    #   tag_list.remove("Sad, Lonely", :parse => true)
    def remove(*names)
      extract_and_apply_options!(names)
      delete_if { |name| names.include?(name) }
      self
    end

    ##
    # Transform the tag_list into a tag string suitable for editing in a form.
    # The tags are joined with <tt>TagList.delimiter</tt> and quoted if necessary.
    #
    # Example:
    #   tag_list = TagList.new("Round", "Square,Cube")
    #   tag_list.to_s # 'Round, "Square,Cube"'
    def to_s
      tags = frozen? ? self.dup : self
      tags.send(:clean!)

      tags.map do |name|
        d = SimpleHashtag.delimiter
        d = Regexp.new d.join('|') if d.kind_of? Array
        name.index(d) ? "\"#{name}\"" : name
      end.join(SimpleHashtag.glue)
    end

    private

    # Convert everything to string, remove whitespace, duplicates, and blanks.
    def clean!
      reject!(&:blank?)
      map!(&:to_s)
      map!(&:strip)
      # map! { |tag| tag.mb_chars.downcase.to_s } if SimpleHashtag.force_lowercase
      # map!(&:parameterize) if SimpleHashtag.force_parameterize

      uniq!
    end


    def extract_and_apply_options!(args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      options.assert_valid_keys :parse

      args.map! { |a| TagListParser.parse(a) } if options[:parse]

      args.flatten!
    end


    ## DEPRECATED
    def self.from(string)
      ActiveRecord::Base.logger.warn <<WARNING
SimpleHashtag::TagList.from is deprecated \
and will be removed from v4.0+, use  \
SimpleHashtag::TagListParser.parse instead
WARNING
      TagListParser.parse(string)
    end


  end
end
