
begin
  col = Article.columns_hash["status"]
  has_col = !col.nil?
  default_ok = col && col.default.to_s == "draft"
  idx = ActiveRecord::Base.connection.index_exists?(:articles, :status)
  if has_col && default_ok && idx
    puts "RESULT: PASS"
  else
    puts "RESULT: FAIL: has_col=#{has_col} default=#{col&.default.inspect} index=#{idx}"
  end
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
