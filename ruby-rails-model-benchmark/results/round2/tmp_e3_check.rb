
begin
  Article.create!(title: "Ruby on Rails Guide", body: "learn rails")
  Article.create!(title: "Something else", body: "unrelated")
  result = Article.ransack(title_or_body_cont: "rails").result
  ok = result.is_a?(ActiveRecord::Relation) && result.count >= 1
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: result_class=#{result.class} count=#{result.count rescue "n/a"}"
rescue NoMethodError => e
  puts "RESULT: FAIL: hallucinated method: #{e.message}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
