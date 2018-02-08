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
          records = records_for_multiple_rules(@rules)
        end
        records.distinct
      end

      private

      def records_for_multiple_rules(rules)
        base_query = base_query_proxy.query
        cypher_options = construct_cypher_options
        match_string = cypher_options[:matches].uniq.join(', ')
        base_query = base_query.match(match_string) unless match_string.blank?
        base_query
          .proxy_as(@model_class, var_name(@model_class))
          .where(cypher_options[:conditions])
      end

      def construct_cypher_options
        @rules.reverse.inject({conditions: '', matches: []}) do |cypher_options, rule|
          if rule.conditions.blank?
            rule_conditions = rule.base_behavior ? "(true)" : "(false)"
          else
            rule_conditions, match_classes = cypher_options_for_rule(rule)
            cypher_options[:matches] += match_classes
          end
          
          if cypher_options[:conditions].blank?
            cypher_options[:conditions] += 'NOT ' if !rule.conditions.blank? && !rule.base_behavior
          else
            cypher_options[:conditions] += rule.base_behavior ? ' OR ' : ' AND NOT'
          end

          cypher_options[:conditions] += ('(' + rule_conditions + ')')
          cypher_options
        end
      end

      def cypher_options_for_rule(rule)
        associations_conditions, model_conditions = bifurcate_conditions(rule.conditions)
        rule_conditions, matches = '', []
        path_start_node = match_node_cypher(@model_class)
        rule_conditions += construct_conditions_string(model_conditions, @model_class, path_start_node) unless model_conditions.blank?
        
        rule_conditions, matches = append_association_conditions(rule_conditions: rule_conditions, conditions_hash: associations_conditions,
                                                                 parent_class: @model_class, path: path_start_node) unless associations_conditions.blank?

        [rule_conditions, matches]
      end

      def append_association_conditions(rule_conditions:, conditions_hash:, parent_class:, path: )
        asso_conditions_string, matches = construct_association_conditions(conditions: conditions_hash,
                                                                           parent_class: parent_class, path: path)
        rule_conditions += ' AND ' if !rule_conditions.blank?
        rule_conditions += asso_conditions_string
        [rule_conditions, matches]
      end

      def construct_association_conditions(conditions:, parent_class:, path:, conditions_string: '', matches: [])
        conditions_string += ' AND ' unless conditions_string.blank?
        conditions.each do |association, conditions|
          relationship = parent_class.associations[association]
          associations_conditions, model_conditions = bifurcate_conditions(conditions)
          
          conditions_string, path, matches = append_model_conditions(relationship: relationship,
                                                                     model_conditions: model_conditions,
                                                                     path: path, matches: matches,
                                                                     conditions_string: conditions_string) 
          conditions_string, matches = construct_association_conditions(conditions: associations_conditions,
                                                                        parent_class: relationship.target_class,
                                                                        conditions_string: conditions_string,
                                                                        path: path, matches: matches) if !associations_conditions.blank?
        end
        [conditions_string, matches]
      end

      def append_model_conditions(relationship:, model_conditions:, path:, conditions_string:, matches:)
        direct_model_conditions = model_conditions.select {|key, _| !relationship.target_class.associations_keys.include?(key)}
        path += append_path(relationship, direct_model_conditions.blank?)
        if !direct_model_conditions.blank?
          matches << match_node_cypher(relationship.target_class)
          conditions_string += ( path + " AND " )
        end
        conditions_string += construct_conditions_string(model_conditions, relationship.target_class, path) if !model_conditions.blank?
        [conditions_string, path, matches]
      end

      def append_path(relationship, without_end_node)
        direction_cypher(relationship) +
        (without_end_node ? '()' : match_node_cypher(relationship.target_class))
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
        class_constant.name.downcase.split('::').join('_')
      end

      def records_for_rule(rule)
        return records_for_rule_without_conditions(rule) if rule.conditions.blank?

        records = base_query_proxy
        where_method = rule.base_behavior ? :where : :where_not
        associations_conditions, model_conditions = bifurcate_conditions(rule.conditions)
        unless model_conditions.blank?
          model_conditions_string = construct_conditions_string(model_conditions, @model_class)
          records = records.send(where_method, model_conditions_string)
        end

        associations_conditions.each do |association, conditions|
          branch_chain = construct_branches(association: association, conditions: conditions,
                                            base_class: @model_class, where_method: where_method)
          records = records.branch { eval(branch_chain)}
        end
        records
      end
      
      def construct_branches(association:, conditions:, base_class:, where_method:, branch_chain:'')
        base_class = base_class.associations[association].target_class
        branch_chain += '.' unless branch_chain.blank?
        branch_chain += association.to_s
        associations_conditions, model_conditions = bifurcate_conditions(conditions)
        unless model_conditions.blank?
          model_conditions_string = construct_conditions_string(model_conditions, base_class)
          branch_chain += ".as(:#{var_name(base_class)}).#{where_method}(\"#{model_conditions_string}\")"
        end
        associations_conditions.each do |association, conditions|
          branch_chain = construct_branches(association: association, conditions: conditions,
                                            base_class: base_class, where_method: where_method, branch_chain: branch_chain)
        end
        branch_chain
      end

      def bifurcate_conditions(conditions)
        conditions.partition{|_, value| value.is_a?(Hash)}.map(&:to_h)
      end

      def bifurcate_model_conditions(model_conditions)
        conditions.partition{|key, _| model_class.associations_keys.include?(key)}.map(&:to_h)
      end

      def records_for_rule_without_conditions(rule)
        rule.base_behavior ? @model_class.all : @model_class.where_not('true')
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

      def construct_conditions_string(conditions_hash, base_class, path='')
        variable_name = var_name(base_class)
        conditions_hash.collect do |key, value|
          if base_class.associations_keys.include?(key)
            condition = condtion_for_path(path: path, variable_name: variable_name,
                                          base_class: base_class, value: value, key: key)
          elsif key == :id 
            condition = condition_for_id(base_class, variable_name, value)
          else
            condition = condition_for_attribute(value, variable_name, key)              
          end
          '(' + condition + ')'
        end.join(' AND ')
      end

      def condition_for_attribute(value, variable_name, attribute)
        lhs = variable_name + '.' + attribute.to_s
        return lhs + ' IS NULL ' if value.nil?
        rhs = [true, false].include?(value) ? value.to_s : "'" + value.to_s + "'"
        lhs + "=" + rhs
      end

      def condtion_for_path(path:, variable_name:, base_class:, value:, key:)
        path = "(#{variable_name})" if path.blank?
        (value ? '' : ' NOT ') + path + append_path(base_class.associations[key], true)
      end

      def condition_for_id(base_class, variable_name, value)
        if base_class.id_property_name == :neo_id
          "ID(#{variable_name})=#{value}"
        else
          variable_name + '.' + base_class.id_property_name.to_s + '=' + "'#{value}'"
        end
      end
    end
  end
end

# simplest way to add `accessible_by` to all ActiveNode models
module Neo4j::ActiveNode::ClassMethods
  include CanCan::ModelAdditions::ClassMethods
end
