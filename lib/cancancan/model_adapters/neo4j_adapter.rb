module CanCan
  module ModelAdapters
    class Neo4jAdapter < AbstractAdapter
      def self.for_class?(model_class)
        model_class <= Neo4j::ActiveNode
      end

      def database_records
        return @model_class.where('false') if @rules.empty?
        return @rules.first.conditions if override_scope

        if @rules.size == 1
          records_for_rule(@rules.first)          
        else
          associations_keys = @model_class.associations_keys
          if @rules.map(&:conditions).map(&:keys).any?{ |key| associations_keys.include?(key) }
            # if there are multiple rules and any one contains condition on association we will consider only first rule
            records_for_rule(@rules.first)
          else
            records = records_for_non_associated_rules(@rules)
          end
        end
      end

      private

      def records_for_rule(rule)
        return records_for_rule_without_conditions(rule) if rule.conditions.blank?
        
        records = @model_class.all
        where_method = rule.base_behavior ? :where : :where_not
        associations_conditions, model_conditions = bifercate_conditions(rule.conditions)
        records = records.send(where_method, model_conditions) unless model_conditions.blank?
  
        associations_conditions.each do |association, conditions|
          branch_chain = construct_branches(association, conditions)
          records = records.branch { eval(branch_chain)}
        end
        records.distinct
      end
      
      def construct_branches(association, conditions, branch_chain='')
        branch_chain += '.' unless branch_chain.blank?
        branch_chain += association.to_s
        associations_conditions, model_conditions = bifercate_conditions(conditions)
        branch_chain += ".where(#{model_conditions})" unless model_conditions.blank?
        associations_conditions.each do |association, conditions|
          branch_chain = construct_branches(association, conditions, branch_chain)
        end
        branch_chain
      end

      def bifercate_conditions(conditions)
        conditions.partition{|_, value| value.is_a?(Hash)}.map(&:to_h)
      end

      def records_for_rule_without_conditions(rule)
        rule.base_behavior ? @model_class.all : @model_class.where_not('true')
      end

      def raise_association_condition_error(associations)
        raise Error,
              "unable to query on multiple association conditions #{associations.join(',')}"
      end

      def override_scope
        conditions = @rules.map(&:conditions).compact
        return unless conditions.any? { |c| c.is_a?(Neo4j::ActiveNode::Query::QueryProxy) }
        return conditions.first if conditions.size == 1
        raise_override_scope_error
      end

      def raise_override_scope_error
        rule_found = @rules.detect { |rule| rule.conditions.is_a?(Neo4j::ActiveNode::Query::QueryProxy) }
        raise Error,
              'Unable to merge an ActiveNode scope with other conditions. '\
              "Instead use a hash for #{rule_found.actions.first} #{rule_found.subjects.first} ability."
      end

      def records_for_non_associated_rules(rules)
        base_class_name = @model_class.name.downcase
        conditions = ''
        rules.reverse.each do |rule|
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
            rule.conditions.each_with_index do |(key, value), index|
              condition += index == 0 ? '(' : ' AND (' 
              value = [true, false].include?(value) ? value.to_s : "'" + value.to_s + "'"
              condition += (base_class_name + '.' + key.to_s + "=" + value)
              condition += ')'
            end
            condition += ')'
          end
          conditions += condition
        end
        @model_class.as(base_class_name.to_sym).where(conditions)
      end
    end
  end
end

# simplest way to add `accessible_by` to all ActiveNode models
module Neo4j::ActiveNode::ClassMethods
  include CanCan::ModelAdditions::ClassMethods
end
