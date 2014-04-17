module SimpleHashtag
  module Hashtaggable
    extend ActiveSupport::Concern

    included do
      has_many :hashtaggings, as: :hashtaggable,  class_name: "SimpleHashtag::Hashtagging", dependent: :destroy
      has_many :hashtags, through: :hashtaggings, class_name: "SimpleHashtag::Hashtag"

      before_save :update_hashtags

      def hashtaggable_content
        self.class.hashtaggable_attribute # to ensure it has been called at least once
        content = self.send(self.class.hashtaggable_attribute_name)
        content.to_s
      end

      def update_hashtags
        self.hashtags = parsed_hashtags
      end

      def parsed_hashtags
        parsed_hashtags = []
        array_of_hashtags_as_string = scan_for_hashtags(hashtaggable_content)
        array_of_hashtags_as_string.each do |s|
          parsed_hashtags << Hashtag.find_or_create_by_name(s[1])
        end
        parsed_hashtags
      end

      def scan_for_hashtags(content)
        match = content.scan(Hashtag::HASHTAG_REGEX)
        match.uniq!
        match
      end
    end

    module ClassMethods
      attr_accessor :hashtaggable_attribute_name

      def hashtaggable_attribute(name=nil)
        self.hashtaggable_attribute_name ||= name || :body
      end

      def tag_counts_on(options = {})
        all_tag_counts(options)
      end

      def tags_on(options = {})
        all_tags(options)
      end

      ##
      # Calculate the tag names.
      # To be used when you don't need tag counts and want to avoid the taggable joins.
      #
      # @param [Hash] options Options:
      #                       * :start_at   - Restrict the tags to those created after a certain time
      #                       * :end_at     - Restrict the tags to those created before a certain time
      #                       * :conditions - A piece of SQL conditions to add to the query. Note we don't join the taggable objects for performance reasons.
      #                       * :limit      - The maximum number of tags to return
      #                       * :order      - A piece of SQL to order by. Eg 'tags.count desc' or 'taggings.created_at desc'
      #                       * :on         - Scope the find to only include a certain context
      def all_tags(options = {})
        options.assert_valid_keys :start_at, :end_at, :conditions, :order, :limit

        ## Generate conditions:
        options[:conditions] = sanitize_sql(options[:conditions]) if options[:conditions]

        ## Generate scope:
        tagging_scope = SimpleHashtag::Hashtagging.select("#{SimpleHashtag::Hashtagging.table_name}.hashtag_id")
        tag_scope = SimpleHashtag::Hashtag.select("#{SimpleHashtag::Hashtag.table_name}.*").order(options[:order]).limit(options[:limit])

        # Joins and conditions
        tagging_conditions(options).each { |condition| tagging_scope = tagging_scope.where(condition) }
        tag_scope     = tag_scope.where(options[:conditions])

        group_columns = "#{SimpleHashtag::Hashtagging.table_name}.hashtag_id"

        # Append the current scope to the scope, because we can't use scope(:find) in RoR 3.0 anymore:
        scoped_select = "#{table_name}.#{primary_key}"
        tagging_scope = tagging_scope.where("#{SimpleHashtag::Hashtagging.table_name}.hashtaggable_id IN(#{safe_to_sql(select(scoped_select))})").group(group_columns)

        tag_scope_joins(tag_scope, tagging_scope)
      end


      ##
      # Calculate the tag counts for all tags.
      #
      # @param [Hash] options Options:
      #                       * :start_at   - Restrict the tags to those created after a certain time
      #                       * :end_at     - Restrict the tags to those created before a certain time
      #                       * :conditions - A piece of SQL conditions to add to the query
      #                       * :limit      - The maximum number of tags to return
      #                       * :order      - A piece of SQL to order by. Eg 'tags.count desc' or 'taggings.created_at desc'
      #                       * :at_least   - Exclude tags with a frequency less than the given value
      #                       * :at_most    - Exclude tags with a frequency greater than the given value
      #                       * :on         - Scope the find to only include a certain context
      def all_tag_counts(options = {})
        options.assert_valid_keys :start_at, :end_at, :conditions, :at_least, :at_most, :order, :limit, :on, :id

        ## Generate conditions:
        options[:conditions] = sanitize_sql(options[:conditions]) if options[:conditions]

        ## Generate joins:
        taggable_join = "INNER JOIN #{table_name} ON #{table_name}.#{primary_key} = #{SimpleHashtag::Hashtagging.table_name}.hashtaggable_id"
        taggable_join << " AND #{table_name}.#{inheritance_column} = '#{name}'" unless descends_from_active_record? # Current model is STI descendant, so add type checking to the join condition


        ## Generate scope:
        tagging_scope = SimpleHashtag::Hashtagging.select("#{SimpleHashtag::Hashtagging.table_name}.hashtag_id, COUNT(#{SimpleHashtag::Hashtagging.table_name}.hashtag_id) AS tags_count")
        tag_scope = SimpleHashtag::Hashtag.select("#{SimpleHashtag::Hashtag.table_name}.*, #{SimpleHashtag::Hashtagging.table_name}.tags_count AS count").order(options[:order]).limit(options[:limit])

        # Joins and conditions
        tagging_scope = tagging_scope.joins(taggable_join)
        tagging_conditions(options).each { |condition| tagging_scope = tagging_scope.where(condition) }
        tag_scope     = tag_scope.where(options[:conditions])

        # GROUP BY and HAVING clauses:
        having = ["COUNT(#{SimpleHashtag::Hashtagging.table_name}.hashtag_id) > 0"]
        having.push sanitize_sql(["COUNT(#{SimpleHashtag::Hashtagging.table_name}.hashtag_id) >= ?", options.delete(:at_least)]) if options[:at_least]
        having.push sanitize_sql(["COUNT(#{SimpleHashtag::Hashtagging.table_name}.hashtag_id) <= ?", options.delete(:at_most)]) if options[:at_most]
        having = having.compact.join(' AND ')

        group_columns = "#{SimpleHashtag::Hashtagging.table_name}.hashtag_id"

        unless options[:id]
          # Append the current scope to the scope, because we can't use scope(:find) in RoR 3.0 anymore:
          scoped_select = "#{table_name}.#{primary_key}"
          tagging_scope = tagging_scope.where("#{SimpleHashtag::Hashtagging.table_name}.hashtaggable_id IN(#{safe_to_sql(select(scoped_select))})")
        end

        tagging_scope = tagging_scope.group(group_columns).having(having)

        tag_scope_joins(tag_scope, tagging_scope)
      end

      def safe_to_sql(relation)
        connection.respond_to?(:unprepared_statement) ? connection.unprepared_statement{relation.to_sql} : relation.to_sql
      end

      private

      def tagging_conditions(options)
        tagging_conditions = []
        tagging_conditions.push sanitize_sql(["#{SimpleHashtag::Hashtagging.table_name}.created_at <= ?", options.delete(:end_at)])   if options[:end_at]
        tagging_conditions.push sanitize_sql(["#{SimpleHashtag::Hashtagging.table_name}.created_at >= ?", options.delete(:start_at)]) if options[:start_at]

        taggable_conditions  = sanitize_sql(["#{SimpleHashtag::Hashtagging.table_name}.hashtaggable_type = ?", base_class.name])
        taggable_conditions << sanitize_sql([" AND #{SimpleHashtag::Hashtagging.table_name}.hashtaggable_id = ?", options[:id]])  if options[:id]

        tagging_conditions.push     taggable_conditions

        tagging_conditions
      end

      def tag_scope_joins(tag_scope, tagging_scope)
        tag_scope = tag_scope.joins("JOIN (#{safe_to_sql(tagging_scope)}) AS #{SimpleHashtag::Hashtagging.table_name} ON #{SimpleHashtag::Hashtagging.table_name}.hashtag_id = #{SimpleHashtag::Hashtag.table_name}.id")
        tag_scope.extending(CalculationMethods)
      end
    end

    def tag_counts_on(options={})
      self.class.tag_counts_on(options.merge(:id => id))
    end

    module CalculationMethods
      def count
        # https://github.com/rails/rails/commit/da9b5d4a8435b744fcf278fffd6d7f1e36d4a4f2
        super(:all)
      end
    end
  end
end
