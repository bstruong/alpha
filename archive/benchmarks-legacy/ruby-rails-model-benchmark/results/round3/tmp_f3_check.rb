
begin
  o = Order.create!(status: "pending")
  o.update!(status: "shipped")
  ts1 = o.reload.shipped_at
  set_on_transition = !ts1.nil?

  sleep 0.05
  o.update!(status: "shipped")  # no actual change (already shipped) -- should be a no-op save
  ts2 = o.reload.shipped_at
  stable_on_noop = (ts1 == ts2)

  ok = set_on_transition && stable_on_noop
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: set_on_transition=#{set_on_transition} stable_on_noop=#{stable_on_noop} ts1=#{ts1.inspect} ts2=#{ts2.inspect}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
