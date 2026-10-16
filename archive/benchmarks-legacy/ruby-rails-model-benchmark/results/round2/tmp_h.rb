result = [1, 2, 3].map { |number| number * 2 }

puts(result == [2, 4, 6] ? "RESULT: PASS" : "RESULT: FAIL: got #{result.inspect}")
