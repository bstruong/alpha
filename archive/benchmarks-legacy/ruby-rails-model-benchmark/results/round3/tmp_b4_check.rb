
begin
  Order.delete_all
  o = Order.create!(status: "paid")
  enum_ok = o.respond_to?(:paid?) && o.paid?
  invalid_raised = false
  begin
    Order.new(status: "bogus_status")
  rescue ArgumentError
    invalid_raised = true
  end
  recent = Order.create!(status: "pending", created_at: 1.day.ago)
  old = Order.create!(status: "pending", created_at: 30.days.ago)
  scope_ok = Order.respond_to?(:recent) && Order.recent.include?(recent) && !Order.recent.include?(old)
  ok = enum_ok && invalid_raised && scope_ok
  if ok
    puts "RESULT: PASS"
  else
    puts "RESULT: FAIL: enum_ok=#{enum_ok} invalid_raised(validate:true)=#{invalid_raised} scope_ok=#{scope_ok}"
  end
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
