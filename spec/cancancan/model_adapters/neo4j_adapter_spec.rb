require 'spec_helper'

if defined? CanCan::ModelAdapters::Neo4jAdapter

  describe CanCan::ModelAdapters::Neo4jAdapter do
    before :each do
      Article.delete_all
      Category.delete_all
      Comment.delete_all
      User.delete_all
      Mention.delete_all
      (@ability = double).extend(CanCan::Ability)
      @article_table = 'article'
      @comment_table = 'comment'
    end

    it 'is for only neo4j classes' do
      expect(CanCan::ModelAdapters::Neo4jAdapter).to_not be_for_class(Object)
      expect(CanCan::ModelAdapters::Neo4jAdapter).to be_for_class(Article)
      expect(CanCan::ModelAdapters::AbstractAdapter.adapter_class(Article))
        .to eq(CanCan::ModelAdapters::Neo4jAdapter)
    end

    it 'finds record' do
      article = Article.create!
      adapter = CanCan::ModelAdapters::AbstractAdapter.adapter_class(Article)
      expect(adapter.find(Article, article.id)).to eq(article)
    end

    it 'does not fetch any records when no abilities are defined' do
      Article.create!
      expect(Article.accessible_by(@ability)).to be_empty
    end

    it 'fetches all articles when one can read all' do
      @ability.can :read, Article
      article = Article.create!
      expect(Article.accessible_by(@ability).to_a).to eq([article])
    end

    it 'fetches only the articles that are published' do
      @ability.can :read, Article, published: true
      article1 = Article.create!(published: true)
      Article.create!(published: false)
      expect(Article.accessible_by(@ability).to_a).to eq([article1])
    end

    it 'fetches any articles which are published or secret' do
      @ability.can :read, Article, published: true
      @ability.can :read, Article, secret: true
      article1 = Article.create!(published: true, secret: false)
      article2 = Article.create!(published: true, secret: true)
      article3 = Article.create!(published: false, secret: true)
      Article.create!(published: false, secret: false)
      expect(Article.accessible_by(@ability).to_a).to eq([article1, article2, article3])
    end

    context 'nested rules' do
      before :each do
        @user = User.create!(name: 'Chunky')
        @cited = Article.create!(published: true)
        @article2 = Article.create!(published: true)
        @mention = Mention.create!(active: true)
        @mention.user = @user
        @cited.mentions << @mention
      end

      
      context 'condition to check non existance of relation on base model' do
        it 'fetches all articles with matching conditions' do
          @ability.can :read, Article, mentions: nil
          expect(Article.accessible_by(@ability).to_a).to eq([@article2])
        end
      end

      context 'condition to check non existance of relation on base model with base model conditions' do
        it 'fetches all articles with matching conditions' do
          @ability.can :read, Article, mentions: nil, published: true
          expect(Article.accessible_by(@ability).to_a).to eq([@article2])
        end
      end

      context 'condition to check non existance of relation on one level deep model' do
        it 'fetches all articles with matching conditions' do
          @article2.mentions << Mention.create!
          @ability.can :read, Article, mentions: {user: nil}
          expect(Article.accessible_by(@ability).to_a).to eq([@article2])
        end
      end

      context 'condition to check non existance of relation on one level deep model with base model conditions' do
        it 'fetches all articles with matching conditions' do
          @article2.mentions << Mention.create!
          @ability.can :read, Article, mentions: {user: nil}, published: true
          expect(Article.accessible_by(@ability).to_a).to eq([@article2])
        end
      end

      context 'with multiple rules' do
        context 'condition to check non existance of relation on base model' do
          it 'fetches all articles with matching conditions' do
            @ability.can :read, Article, mentions: nil
            @ability.can :manage, Article, published: false
            expect(Article.accessible_by(@ability).to_a).to eq([@article2])
          end
        end

        context 'condition to check non existance of relation on base model with base model conditions' do
          it 'fetches all articles with matching conditions' do
            @ability.can :manage, Article, published: false
            @ability.can :read, Article, mentions: nil, published: true
            expect(Article.accessible_by(@ability).to_a).to eq([@article2])
          end
        end

        context 'condition to check non existance of relation on one level deep model' do
          it 'fetches all articles with matching conditions' do
            @article2.mentions << Mention.create!
            @ability.can :read, Article, mentions: {user: nil}
            @ability.can :manage, Article, published: false
            expect(Article.accessible_by(@ability).to_a).to eq([@article2])
          end
        end

        context 'condition to check non existance of relation on one level deep model with base model conditions' do
          it 'fetches all articles with matching conditions' do
            @article2.mentions << Mention.create!
            @ability.can :manage, Article, published: false
            @ability.can :read, Article, mentions: {user: nil}, published: true
            expect(Article.accessible_by(@ability).to_a).to eq([@article2])
          end
        end
      end

      context 'condition on 1st level deep model' do
        it 'fetches any articles which we are cited in' do
          @ability.can :read, Article, mentions: { active: true }
          @ability.can :read, Article, published: false
          expect(Article.accessible_by(@ability).to_a).to eq([@cited])
        end
      end

      context 'condition on 2nd level deep model' do
        it 'fetches any articles which we are cited in' do
          @ability.can :read, Article, mentions: {user: {name: 'Chunky'} }
          @ability.can :read, Article, published: false
          expect(Article.accessible_by(@ability).to_a).to eq([@cited])
        end
      end

      context 'condition on both 1st level and 2nd level deep model' do
        it 'fetches any articles which we are cited in' do
          @ability.can :read, Article, mentions: {active: true, user: {name: 'Chunky'} }
          @ability.can :read, Article, published: false
          expect(Article.accessible_by(@ability).to_a).to eq([@cited])
        end
      end

      context 'Combination of can and cannot rule' do
        it 'fetches any articles which we are cited in' do
          @ability.can :read, Article, mentions: {active: true, user: {name: 'Chunky'} }
          @ability.cannot :read, Article, published: false
          expect(Article.accessible_by(@ability).to_a).to eq([@cited])
        end
      end
    end

    it 'fetches only the articles that are published and not secret' do
      @ability.can :read, Article, published: true
      @ability.cannot :read, Article, secret: true
      article1 = Article.create!(published: true, secret: false)
      Article.create!(published: true, secret: true)
      Article.create!(published: false, secret: true)
      Article.create!(published: false, secret: false)
      expect(Article.accessible_by(@ability).to_a).to eq([article1])
    end

    it 'only reads comments for articles which are published' do
      @ability.can :read, Comment, article: { published: true }
      comment1 = Comment.create!(article: Article.create!(published: true))
      Comment.create!(article: Article.create!(published: false))
      expect(Comment.accessible_by(@ability).to_a).to eq([comment1])
    end

    it 'should only read articles which are published and in visible categories' do
      @ability.can :read, Article, category: { visible: true }, published: true
      Article.create!(published: true)
      Article.create!(published: false)
      article3 = Article.create!(published: true, category: Category.create!(visible: true))
      expect(Article.accessible_by(@ability).to_a).to eq([article3])
    end

    it 'should only read categories once even if they have multiple articles' do
      @ability.can :read, Category, articles: { published: true }
      @ability.can :read, Article, published: true
      category = Category.create!
      Article.create!(published: true, category: category)
      Article.create!(published: true, category: category)
      expect(Category.accessible_by(@ability).to_a).to eq([category])
    end

    it 'raises an exception when trying to merge scope with other conditions' do
      @ability.can :read, Article, published: true
      @ability.can :read, Article, Article.where(secret: true)
      expect(-> { Article.accessible_by(@ability) })
        .to raise_error(CanCan::Error,
                        'Unable to merge an ActiveNode scope with other conditions. '\
                        'Instead use a hash for read Article ability.')
    end

    it 'allows a scope for conditions' do
      @ability.can :read, Article, Article.where(secret: true)
      article1 = Article.create!(secret: true)
      Article.create!(secret: false)
      expect(Article.accessible_by(@ability).to_a).to eq([article1])
      end

    it 'only reads comments for visible categories through articles' do
      @ability.can :read, Comment, article: { category: { visible: true } }
      comment1 = Comment.create!(article: Article.create!(category: Category.create!(visible: true)))
      Comment.create!(article: Article.create!(category: Category.create!(visible: false)))
      expect(Comment.accessible_by(@ability)).to eq([comment1])
    end

    it 'does not allow to fetch records when ability with just block present' do
      @ability.can :read, Article do
        false
      end
      expect(-> { Article.accessible_by(@ability) }).to raise_error(CanCan::Error)
    end

    it 'should support more than one deeply nested conditions' do
      @ability.can :read, Comment, article: {
        category: {
          name: 'foo', visible: true
        }
      }
      expect { Comment.accessible_by(@ability) }.to_not raise_error
    end

    it 'returns empty set if no abilities match' do
      expect(@ability.model_adapter(Article, :read).database_records).to be_empty
    end

    it 'returns empty set for cannot clause' do
      @ability.cannot :read, Article
      expect(@ability.model_adapter(Article, :read).database_records).to be_empty
    end

    it 'returns cypher for single `can` definition in front of default `cannot` condition' do
      @ability.cannot :read, Article
      @ability.can :read, Article, published: false, secret: true
      expect(@ability.model_adapter(Article, :read).database_records.to_cypher)
        .to include("WHERE ((false)) OR ((article.published=false) AND (article.secret=true))")
    end

    it 'returns true condition for single `can` definition in front of default `can` condition' do
      @ability.can :read, Article
      @ability.can :read, Article, published: false, secret: true
      expect(@ability.model_adapter(Article, :read).database_records.to_cypher).to include("(true)")
    end

    it 'returns `false condition` for single `cannot` definition in front of default `cannot` condition' do
      @ability.cannot :read, Article
      @ability.cannot :read, Article, published: false, secret: true
      expect(@ability.model_adapter(Article, :read).database_records.to_cypher).to include("(false)")
    end

    it 'returns `not (condition)` for single `cannot` definition in front of default `can` condition' do
      @ability.can :read, Article
      @ability.cannot :read, Article, published: false, secret: true
      expect(@ability.model_adapter(Article, :read).database_records.to_cypher)
        .to include("WHERE ((true)) AND NOT((article.published=false) AND (article.secret=true))")
    end

    it 'merges :all conditions with other conditions' do
      user = User.create!(name: 'Chunky')
      article = Article.create!(user: user)
      ability = Ability.new(user)
      ability.can :manage, :all
      ability.can :manage, Article, user: {name: user.name}
      expect(Article.accessible_by(ability)).to eq([article])
    end

    it 'should not execute a scope when checking ability on the class' do
      relation = Article.where(secret: true)
      @ability.can :read, Article, relation do |article|
        article.secret == true
      end

      allow(relation).to receive(:count).and_raise('Unexpected scope execution.')

      expect { @ability.can? :read, Article }.not_to raise_error
    end


    it 'returns appropriate sql conditions in complex case' do
      @ability.can :read, Article
      @ability.can :manage, Article, name: 'Chunky'
      @ability.can :update, Article, published: true
      @ability.cannot :update, Article, secret: true
      expect(@ability.model_adapter(Article, :update).database_records.to_cypher)
        .to include("((article.name='Chunky')) OR ((article.published=true)) AND NOT((article.secret=true))")
      expect(@ability.model_adapter(Article, :manage).database_records.to_cypher).to include("(article.name=")
      expect(@ability.model_adapter(Article, :read).database_records.to_cypher).to include("(true)")
    end

    context 'with namespaced models' do
      it 'fetches all namespace::table_x when one is related by table_y' do
        user = User.create!(name: 'Chunky')

        ability = Ability.new(user)
        ability.can :read, Namespace::TableX, table_zs: { user: {name: 'Chunky'} }

        table_x = Namespace::TableX.create!
        table_z = Namespace::TableZ.create(user: user)
        table_x.table_zs << table_z
        expect(Namespace::TableX.accessible_by(ability)).to eq([table_x])
      end
    end

    #TODO Fix code to pass this
    # it 'fetches only associated records when using with a scope for conditions' do
    #   @ability.can :read, Article, Article.where(secret: true)
    #   category1 = Category.create!(visible: false)
    #   category2 = Category.create!(visible: true)
    #   article1 = Article.create!(secret: true)
    #   article1.category = category1
    #   article2 = Article.create!(secret: true)
    #   article2.category = category2
    #   expect(category1.articles.accessible_by(@ability).to_a).to eq([article1])
    # end
  end
end
