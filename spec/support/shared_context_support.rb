shared_context 'match expectations' do
  it 'fetches all articles with matching conditions' do
    expect(Article.accessible_by(@ability).to_a).to eq([accessible_article])
    expect(@ability).to be_able_to(:read, accessible_article)
    expect(@ability).not_to be_able_to(:read, not_accessible_article)
  end
end