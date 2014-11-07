ActiveRecord::Calculations
module ActiveRecord
  module Calculations
    def pluck_hash_quick(*column_names)
      column_names.map! do |column_name|
        if column_name.is_a?(Symbol) && attribute_alias?(column_name)
          attribute_alias(column_name)
        else
          column_name.to_s
        end
      end

      if has_include?(column_names.first)
        construct_relation_for_association_calculations.pluck(*column_names)
      else
        relation = spawn
        relation.select_values = column_names.map { |cn|
          columns_hash.key?(cn) ? arel_table[cn] : cn
        }
        result = klass.connection.select_all(relation.arel, nil, bind_values)
        columns = result.columns.map do |key|
          klass.column_types.fetch(key) {
            result.column_types.fetch(key) { result.identity_type }
          }
        end

        result.rows.map do |values|
          {}.tap do |hash|
            values.zip(columns, result.columns).each do |v|
              hash[v[2]] = v[1].type_cast v[0]
            end
          end
        end
      end
    end

    def pluck_hash(*column_names)
      column_names.map! do |column_name|
        if column_name.is_a?(Symbol) && attribute_alias?(column_name)
          attribute_alias(column_name)
        else
          column_name.to_s
        end
      end

      if has_include?(column_names.first)
        construct_relation_for_association_calculations.pluck(*column_names)
      else
        relation = spawn
        relation.select_values = column_names.map { |cn|
          columns_hash.key?(cn) ? arel_table[cn] : cn
        }
        result = klass.connection.select_all(relation.arel, nil, bind_values)
        columns = result.columns.map do |key|
          klass.column_types.fetch(key) {
            result.column_types.fetch(key) { result.identity_type }
          }
        end

        result.rows.map do |values|
          {}.tap do |hash|
            values.zip(columns, result.columns).each do |v|
              single_attr_hash = { v[2] => v[0] }
              hash[v[2]] = v[1].type_cast klass.initialize_attributes(single_attr_hash).values.first
            end
          end
        end
      end
    end
  end
end

class ThinSerializer
  class << self
    attr_accessor :_attributes, :_virtual_attributes, :_associations

    def inherited(base)
      base._attributes = (_attributes || []).dup
      base._virtual_attributes = (_virtual_attributes || []).dup
      base._associations = (_associations || []).dup
    end

    def attributes(*attrs)
      attrs.each { |name| attribute(name) }
    end

    def attribute(name, select = nil)
      @_attributes.push [name.to_s, select]
    end

    def virtual_attributes(*attrs)
      attrs.each { |name| virtual_attribute(name) }
    end

    def virtual_attribute(name, select = nil)
      @_virtual_attributes.push [name.to_s, select]
    end

    def has_many(attr_name, foreign_key, serializer, klass = nil)
      association(:many, attr_name, foreign_key, serializer, klass)
    end

    def has_one(attr_name, foreign_key, serializer, klass = nil)
      association(:one, attr_name, foreign_key, serializer, klass)
    end

    def belongs_to(attr_name, foreign_key, serializer, klass = nil)
      association(:belongs, attr_name, foreign_key, serializer, klass)
    end

  private
    def association(type, attr_name, foreign_key, serializer, klass)
      klass ||= attr_name.to_s.singularize.camelize.constantize
      scope = if block_given?
        yield
      else
        klass.all
      end
      @_associations.push attr_name: attr_name.to_s, klass: klass,
        foreign_key: foreign_key.to_s, serializer: serializer,
        scope: scope, type: type
    end
  end

  def initialize(scope, klass = nil, table_name = nil)
    @scope = scope
    @klass = klass || @scope.klass
    @table_name = table_name || @klass.table_name
    column_names = @klass.columns.map(&:name)
    @attributes = self.class._attributes.select { |attr| column_names.include?(attr[0]) || attr[1] }
    @virtual_attributes = self.class._virtual_attributes
    @computed_attributes = self.class._attributes.select { |attr| respond_to?(attr[0], false) }

    # need id for associations
    unless !!attributes_with_virtual.find { |attr| attr[0] == "id" }
      @virtual_attributes << ["id", nil]
    end

    # need belongs_to columns
    self.class._associations.each do |assoc|
      if assoc[:type] == :belongs
        unless !!attributes_with_virtual.find { |attr| attr[0] == assoc[:foreign_key] }
          @virtual_attributes << [assoc[:foreign_key], nil]
        end
      end
    end
  end

  def serializable_hash
    @serializable_hash ||= begin
      entries = @scope.pluck_hash_quick(*select_values)
      process_associations(entries)
      process_entries entries
    end
  end

  def serializable_hash_grouped_by(attr_name)
    attr_name = attr_name.to_s
    unless attributes_with_virtual.find { |attr| attr[0] == attr_name }
      @virtual_attributes << [attr_name, nil]
    end
    values = select_values

    entries = @scope.pluck_hash_quick(*values)
    process_associations(entries)

    entries.group_by { |entry| entry[attr_name] }.tap do |grouped_entries|
      grouped_entries.each_pair do |k, v|
        process_entries(v)
      end
    end
  end

  def as_json
    serializable_hash
  end

  def to_json
    as_json.to_json
  end

  def method_missing(met, *args, &block)
    if @record_attributes && !block_given?
      met_s = met.to_s
      if args.size == 1 && met.last == "="
        return @record_attributes[met_s[0, met_s.size-1]] = args.first
      elsif args.size == 0 && @record_attributes.key?(met_s)
        return @record_attributes[met_s]
      end
    end

    super
  end

private
  attr_reader :record_attributes
  def attribute_select_value(name, select)
    if select
      "(#{select}) as #{name}"
    else
      "#{@table_name}.#{name}"
    end
  end

  def attributes_with_virtual
    @attributes + @virtual_attributes
  end

  def includes_id?(attributes)
    !!attributes.find { |attr| attr[0] == "id" }
  end

  def process_entries(entries)
    entries.each do |entry|
      process_entry(entry)
    end

    entries
  end

  def select_values
    attributes_with_virtual.map do |attr|
      attribute_select_value(*attr)
    end
  end

  def process_associations(entries)
    unless self.class._associations.empty?
      self.class._associations.each do |assoc_data|
        scope = assoc_data[:scope]
        if [:many, :one].include?(assoc_data[:type])
          scope = scope.where("#{assoc_data[:klass].table_name}.#{assoc_data[:foreign_key]} IN (?)",
            entries.map { |entry| entry["id"] })
        elsif assoc_data[:type] == :belongs
          scope = scope.where("#{assoc_data[:klass].table_name}.id IN (?)",
            entries.map { |entry| entry[assoc_data[:foreign_key]] }.uniq)
        else
          raise "Unknown association type #{assoc_data[:type]}"
        end

        assocs = if assoc_data[:type] == :belongs
          assoc_data[:serializer].new(scope)
          .serializable_hash_grouped_by("id")
        else
          assoc_data[:serializer].new(scope)
          .serializable_hash_grouped_by(assoc_data[:foreign_key])
        end

        entries.each do |entry|
          if assoc_data[:type] == :many
            entry[assoc_data[:attr_name]] = Array(assocs[entry["id"]])
          elsif assoc_data[:type] == :one
            entry[assoc_data[:attr_name]] = Array(assocs[entry["id"]]).first
          elsif assoc_data[:type] == :belongs
            entry[assoc_data[:attr_name]] = assocs[entry[assoc_data[:foreign_key]]].first
          end
        end
      end
    end
  end

  def process_entry(entry)
    @record_attributes = entry
    @computed_attributes.each do |attr|
      entry[attr[0]] = public_send(attr[0])
    end

    @virtual_attributes.each do |attr|
      entry.delete(attr[0])
    end
    @record_attributes = nil
  end
end
