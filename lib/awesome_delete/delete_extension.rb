module AwesomeDelete
  module DeleteExtension
    def delete_collection ids, all_associations_name = []
      #check if there is like *_destroy callback (where(id: ids).destroy_all OR delete_all)

      #find has_many dependent: :destroy associations (remove has_many through)

      #support polymorphic, counter_cahce, touch

      #all_associations_name is added to support counter_cahce and touch
      @@all_associations_name = all_associations_name

      if @@all_associations_name.blank?
        @@all_associations_name = get_associations_name << self.name
      end

      # STI
      if column_names.include? inheritance_column
        where(id: ids).pluck(inheritance_column).uniq.each do |type|
          subklass = type.constantize
          subklass.delete_self_collection(ids)
          delete_assoicated_collection(ids, subklass.has_many_assoications - has_many_assoications)
        end
      else
        delete_self_collection(ids)
      end
      delete_assoicated_collection(ids, has_many_assoications)
    end

    def has_many_assoications
      @has_many_assoications ||= reflect_on_all_associations(:has_many).select do |association|
                                 association.is_a?(ActiveRecord::Reflection::HasManyReflection) && association.options.deep_symbolize_keys.has_key?(:dependent)
                               end
    end

    def can_directly_delete_all?
      not_handle_destroy_callback? && not_handle_counter_cache_or_touch?
    end

    def not_handle_destroy_callback?
      #association.rb(from has_many dependent: :*)
      destroy_callback_location = /lib\/active_record\/associations\/builder\/association.rb/

      destroy_callbacks = _destroy_callbacks.to_a.select do |callback|
                            callback.raw_filter.is_a?(String) || callback.raw_filter.is_a?(Symbol) ||
                            callback.raw_filter.to_s.match(destroy_callback_location)
                          end
      has_many_assoications.count == destroy_callbacks.count
    end

    def not_handle_counter_cache_or_touch?
      belongs_to_assoications = reflect_on_all_associations(:belongs_to).select do |association|
                                  association.options.deep_symbolize_keys.has_key?(:touch) || association.options.deep_symbolize_keys.has_key?(:counter_cahce)
                                end
      associated_class_names = belongs_to_assoications.map(&:class_name)
      #avoid to unnecessary handle
      (@@all_associations_name & associated_class_names) == associated_class_names
    end

    def delete_self_collection ids
      if can_directly_delete_all?
        where(id: ids).delete_all
      else
        where(id: ids).destroy_all
      end
    end

    def delete_assoicated_collection ids, associations
      associations.each do |association|
        association_class = association.klass

        #polymorphic
        if association.type
          association_class.delete_collection association_class.where(association.foreign_key => ids, association.type => self.name).pluck(:id), @@all_associations_name
        else
          association_class.delete_collection association_class.where(association.foreign_key => ids).pluck(:id), @@all_associations_name
        end
      end
    end

    def get_associations_name
      return [] if has_many_assoications.blank?
      associations_name = []

      has_many_assoications.each do |association|
        associations_name << association.class_name
        associations_name += association.class_name.constantize.get_associations_name
      end
      associations_name
    end
  end
end