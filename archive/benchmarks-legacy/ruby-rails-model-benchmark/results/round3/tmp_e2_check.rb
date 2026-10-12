
begin
  a = Article.create!(title: "T", body: "B")
  responds = a.respond_to?(:cover_image)
  a.cover_image.attach(io: StringIO.new("hello"), filename: "test.txt", content_type: "text/plain")
  attached = a.cover_image.attached?
  ok = responds && attached
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: responds=#{responds} attached=#{attached}"
rescue NoMethodError => e
  puts "RESULT: FAIL: hallucinated method: #{e.message}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
