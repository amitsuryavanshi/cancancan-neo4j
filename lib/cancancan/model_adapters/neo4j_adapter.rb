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
          rule.base_behaviour ? @model_class.where(rule.conditions) : @model_class.where_not(rule.conditions)
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
          if rule.base_behaviour
            records = records | @model_class.where(rule.conditions)
          else
            records = records & @model_class.where_not(rule.conditions)
          end
        end
        records
      end

      def non_associated_rule_records(records, rules)
        can_rules = rules.select{|rule| rule.base_behaviour}
        base_class_name = @model_class.name.downcase
        conditions = '(true)'
        can_rules.each do |rule|
          condition = ' OR ('
          rule.conditions.each do |key, value|
            condition += (base_class_name + '.' + key.to_s + '=' + value.to_s)
          end
          condition += ')'
        end
        conditions += condition
      end
    end
  end
end

# simplest way to add `accessible_by` to all ActiveNode models
module Neo4j::ActiveNode::ClassMethods
  include CanCan::ModelAdditions::ClassMethods
end
