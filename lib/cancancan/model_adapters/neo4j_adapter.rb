module CanCan
  module ModelAdapters
    class Neo4jAdapter < AbstractAdapter
      def self.for_class?(model_class)
        model_class <= Neo4j::ActiveNode
      end

      def database_records
        if @rules.empty?
          @model_class.where('false') # empty collection proxy
        elsif @rules.size == 1
          rule = @rules.first
          rule.base_behavior ? @model_class.where(rule.conditions) : @model_class.where_not(rule.conditions)
        else
          rules = {rules_with_association: [], rules_without_association: []}
          associations_keys = @model_class.associations_keys
          @rules.each { |rule| rule.conditions.keys.any?{ |key| associations_keys.include?(key) } ? rules[:rules_with_association] << rule : rules[:rules_without_association] << rule }
          records = association_rule_records(rules[:rules_with_association])
          records = non_associated_rule_records(records, rules[:rules_without_association])
        end
      end

      private

      def association_rule_records(rules)
        records = []
        rules.each do |rule|
          if rule.base_behavior
            records = records | @model_class.where(rule.conditions)
          else
            records = records & @model_class.where_not(rule.conditions)
          end
        end
        records
      end

      def non_associated_rule_records(records, rules)
        base_class_name = @model_class.name.downcase
        conditions = ''
        rules.each do |rule|
          condition = ''
          if rule.conditions.blank?
            if rule.base_behavior
              condition = conditions.blank? ? "(true)" : " OR (true)"
            else
              condition = conditions.blank? ? "(false)" : " AND (false)"
            end
          else
            if rule.base_behavior   
              condition = conditions.blank? ? '(' : ' OR ('
            else
              condition = conditions.blank? ? ' NOT (' : ' AND NOT ('
            end
            rule.conditions.each do |key, value|
              condition += (base_class_name + '.' + key.to_s + "='" + value.to_s + "'")
            end
            condition += ')'
          end
          conditions += condition
        end
        records = records | @model_class.as(base_class_name.to_sym).where(conditions)
      end
    end
  end
end

# simplest way to add `accessible_by` to all ActiveNode models
module Neo4j::ActiveNode::ClassMethods
  include CanCan::ModelAdditions::ClassMethods
end
