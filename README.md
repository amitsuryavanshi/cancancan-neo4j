# CanCanCan-Neo4j


This is the adapter for the [CanCanCan](https://github.com/CanCanCommunity/cancancan) authorisation
library to automatically generate cypher queries from ability rules. It returns QueryProxy object for resourses.

Adds support for neo4j >= 9.0

## Ruby Versions Supported

Ruby >= 2.0.0

## Usage

In your `Gemfile`, insert the following line:

```ruby
gem 'cancancan'
gem 'cancancan-neo4j'
```

## Caution 

If you specify multiple can or can not rules with anyone having condition on association, you will get a performance hit.  
