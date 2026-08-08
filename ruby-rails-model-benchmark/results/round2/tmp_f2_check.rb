
begin
  a = Article.create!(title: "T", body: "B")
  c = Comment.create!(body: "nice", commentable: a)
  ok = a.respond_to?(:comments) && a.comments.include?(c)
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: respond_to=#{a.respond_to?(:comments)} includes=#{a.respond_to?(:comments) ? a.comments.include?(c) : "n/a"}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
