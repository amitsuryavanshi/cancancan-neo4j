require 'cancancan/neo4j/cypher_constructor_helper'

module CanCan
  module ModelAdapters
    class Neo4jAdapter < AbstractAdapter
      include CanCanCan::Neo4j::CypherConstructorHelper

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
            rule_conditions = condition_for_rule_without_conditions(rule) 
          else
            rule_conditions, match_classes = cypher_options_for_rule(rule)
            cypher_options[:matches] += match_classes
          end
          
          cypher_options[:conditions] = append_and_or_to_conditions(cypher_options[:conditions], rule)

          cypher_options[:conditions] += ('(' + rule_conditions + ')')
          cypher_options
        end
      end

      def append_and_or_to_conditions(conditions_string, rule)
        connector = conditions_string.blank? ? '' : conditions_connector(rule)
        connector += 'NOT' if append_not_to_conditions?(rule)
        conditions_string + connector
      end

      def append_not_to_conditions?(rule)
        !rule.conditions.blank? && !rule.base_behavior
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

      def base_query_proxy
        @model_class.as(var_name(@model_class))
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
    end
  end
end

# simplest way to add `accessible_by` to all ActiveNode models
module Neo4j::ActiveNode::ClassMethods
  include CanCan::ModelAdditions::ClassMethods
end
