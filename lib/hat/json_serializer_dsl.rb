require_relative 'serializer_registry'

module Hat
  module JsonSerializerDsl

    def self.apply_to(serializer_class)
      serializer_class.class_attribute :_attributes
      serializer_class.class_attribute :_relationships
      serializer_class.class_attribute :_includable
      serializer_class.class_attribute :_serializes

      serializer_class._attributes = []
      serializer_class._relationships = { has_ones: [], has_manys: [] }

      serializer_class.extend(self)
    end

    def serializes(klass)
      self._serializes = klass
      Hat::SerializerRegistry.instance.register(_type, klass, self)
    end

    def has_ones
      self._relationships[:has_ones]
    end

    def has_manys
      self._relationships[:has_manys]
    end

    def attributes(*args)
      self._attributes = args
    end

    def has_one(has_one)
      self.has_ones << has_one
    end

    def has_many(has_many)
      self.has_manys << has_many
    end

    def includable(*includes)
      self._includable = RelationIncludes.new(*includes)
    end

    def _type
      if self.ancestors.any? { |klass| klass == Hat::Sideloading::JsonSerializer }
        :sideloading
      elsif self.ancestors.any? { |klass| klass == Hat::Nesting::JsonSerializer }
        :nesting
      else
        raise "Unsupported serializer type. Must be sideloading or nesting serializer."
      end
    end

  end
end
