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
          records = records_for_rule(@rules.first)          
        else
          associations_keys = @model_class.associations_keys
          if @rules.map(&:conditions).map(&:keys).flatten.any?{ |key| associations_keys.include?(key) }
            # if there are multiple rules and any one contains condition on association we will consider only first rule
            records = records_for_rule_with_associations(@rules)
          else
            records = records_for_non_associated_rules(@rules)
          end
        end
        records.distinct
      end

      private

      def records_for_rule_with_associations(rules)
        query_proxy = construct_matches.proxy_as(@model_class, var_name(@model_class))
        
        conditions_strig = construct_conditions
        query_proxy.where(conditions_strig)
      end

      def construct_conditions
        @rules.each_with_index.inject('') do |conditions, (rule, index)|
          if rule.conditions.blank?
            rule_conditions = rule.base_behavior ? "(true)" : "(false)"
          else
            associations_conditions, model_conditions = bifercate_conditions(rule.conditions)
            rule_conditions = ''
            rule_conditions += construct_conditions_for_model(model_conditions, @model_class) unless model_conditions.blank?
            rule_conditions += ' AND ' if !rule_conditions.blank? && !associations_conditions.blank?
            rule_conditions += construct_association_conditions(associations_conditions, @model_class) unless associations_conditions.blank?
          end
          if conditions.blank?
            conditions += rule.base_behavior ? '' : ' NOT'
          else
            conditions += rule.base_behavior ? ' OR ' : 'AND NOT'
          end
          conditions += ('(' + rule_conditions + ')')
        end
      end

      def construct_association_conditions(conditions, parent_class, conditions_string='')
        conditions_string += ' AND ' unless conditions_string.blank?
        conditions.each do |association, conditions|
          base_class = parent_class.associations[association].target_class
          associations_conditions, model_conditions = bifercate_conditions(conditions)
          conditions_string += construct_conditions_for_model(model_conditions, base_class) unless model_conditions.blank?
          conditions_string = construct_association_conditions(associations_conditions, base_class, conditions_string) unless associations_conditions.blank?       
        end
        conditions_string
      end

      def construct_conditions_for_model(conditions_hash, class_constant)
        class_name = var_name(class_constant)
        conditions = construct_conditions_string(conditions_hash, class_name)
      end

      def construct_matches
        query = base_query_proxy.query
        @rules.each do |rule|
          rule.associations_hash.each do |association, nested_hash|
            match_string = get_match(@model_class, association)
            if nested_hash.empty?
              query = rule.base_behavior ? query.optional_match(match_string) : query.match(match_string)
            else
              base_class = @model_class.associations[association].target_class
              query = nested_match_string(match_string, base_class, nested_hash, rule.base_behavior, query)              
            end
          end
        end
        query
      end

      def nested_match_string(match_string, base_class, nested_hash, base_behavior, query)
        nested_hash.each do |association, nested_associations|
          match_string += partial_nested_match(base_class, association)
          if nested_associations.empty?
            query = base_behavior ? query.optional_match(match_string) : query.match(match_string)
          else
            base_class = base_class.associations[association].target_class
            nested_match_string(match_string, base_class, nested_associations, base_behavior, query)
          end
        end
        query
      end

      def partial_nested_match(base_class, association)
        relationship = base_class.associations[association]
        direction_cypher(relationship) +
        match_node_cypher(relationship.target_class)
      end

      def get_match(base_class, match)
        relationship = base_class.associations[match]
        match_node_cypher(base_class) +
        direction_cypher(relationship) +
        match_node_cypher(relationship.target_class)
      end

      def match_node_cypher(node_class)
        "(#{var_name(node_class)}:`#{node_class.mapped_label_name}`)"
      end

      def direction_cypher(relationship)
        case relationship.direction
        when :out
          "-#{relationship_type(relationship)}->"
        when :in
          "<-#{relationship_type(relationship)}-"
        when :both
          "-#{relationship_type(relationship)}-"
        end
      end

      def relationship_type(relationship)
        "[:`#{relationship.relationship_type}`]"
      end

      def base_query_proxy
        @model_class.as(var_name(@model_class))
      end

      def var_name(class_constant)
        class_constant.name.downcase
      end

      def records_for_rule(rule)
        return records_for_rule_without_conditions(rule) if rule.conditions.blank?

        records = base_query_proxy
        where_method = rule.base_behavior ? :where : :where_not
        associations_conditions, model_conditions = bifercate_conditions(rule.conditions)
        records = records.send(where_method, model_conditions) unless model_conditions.blank?
  
        associations_conditions.each do |association, conditions|
          branch_chain = construct_branches(association, conditions)
          records = records.branch { eval(branch_chain)}
        end
        records
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
            condition += (construct_conditions_string(rule.conditions, base_class_name) + ')')
          end
          conditions += condition
        end
        @model_class.as(base_class_name.to_sym).where(conditions)
      end

      def construct_conditions_string(conditions_hash, base_class_name)
        condition = ''
        conditions_hash.each_with_index do |(key, value), index|
          condition += index == 0 ? '(' : ' AND (' 
          value = [true, false].include?(value) ? value.to_s : "'" + value.to_s + "'"
          condition += (base_class_name + '.' + key.to_s + "=" + value)
          condition += ')'
        end
        condition
      end
    end
  end
end

# simplest way to add `accessible_by` to all ActiveNode models
module Neo4j::ActiveNode::ClassMethods
  include CanCan::ModelAdditions::ClassMethods
end
