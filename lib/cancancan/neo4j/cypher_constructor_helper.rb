module CanCanCan
  module Neo4j
		module CypherConstructorHelper

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

      def condition_for_rule_without_conditions(rule)
        rule.base_behavior ? "(true)" : "(false)"
      end

      def conditions_connector(rule)
        rule.base_behavior ? ' OR ' : ' AND '
      end

      def var_name(class_constant)
        class_constant.name.downcase.split('::').join('_')
      end
		end
  end
end
