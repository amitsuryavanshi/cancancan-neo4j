module CanCan
  module ModelAdapters
    class Neo4jAdapter < AbstractAdapter
      def self.for_class?(model_class)
        model_class <= Neo4j::ActiveNode
      end

      def database_records
        if @rules.empty?
          @model_class.where(id: 0) # empty collection proxy
        else

          @rules.each do |rule|
            if rule.base_behaviour
              # need to join all can rules with where and or.
              @model_class.where(rule.conditions)
            else
              # need to join all can_not rules with where_not
              @model_class.where_not(rule.conditions)
            end
          end
          
      end
    end
  end
end

# simplest way to add `accessible_by` to all ActiveNode models
module Neo4j::ActiveNode::ClassMethods
  include CanCan::ModelAdditions::ClassMethods
end
