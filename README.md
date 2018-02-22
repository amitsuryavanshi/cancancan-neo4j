# CanCanCan-Neo4j

[![Code Climate Badge](https://codeclimate.com/github/CanCanCommunity/cancancan.svg)](https://codeclimate.com/github/amitsuryavanshi/cancancan-neo4j)

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
Defining cancan rules:

```ruby
can :read, Article, author: { name: 'Chunky' }
```
here name is a property on Author and Article has 'has_one' relation with Author.

