
begin
  User.delete_all
  u1 = User.new(email: "a@example.com", username: "alice", age: 30)
  v1 = u1.valid?
  u2 = User.new(email: nil, username: "al", age: nil)
  v2 = u2.valid?  # should be invalid: no email, username too short
  User.create!(email: "dup@example.com", username: "bobby", age: 20)
  u3 = User.new(email: "DUP@example.com", username: "carly", age: 25)
  v3 = u3.valid?  # should be invalid: case-insensitive dup email
  u4 = User.new(email: "x@example.com", username: "validname", age: nil)
  v4 = u4.valid?  # age nil should be allowed -> valid

  ok = v1 == true && v2 == false && v3 == false && v4 == true
  if ok
    puts "RESULT: PASS"
  else
    puts "RESULT: FAIL: v1=#{v1} v2=#{v2}(errs=#{u2.errors.full_messages}) v3=#{v3}(errs=#{u3.errors.full_messages}) v4=#{v4}(errs=#{u4.errors.full_messages})"
  end
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
