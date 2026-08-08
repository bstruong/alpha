
begin
  a = Article.create!(title: "T", body: "B")
  a.archive!
  active_excludes = Article.active.exclude?(a) rescue nil
  ok = a.reload.archived == true && active_excludes == true
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: archived=#{a.reload.archived} active_excludes=#{active_excludes}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
