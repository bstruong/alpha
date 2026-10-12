
begin
  params = ActionController::Parameters.new(
    article: {
      title: "T", body: "B", status: "draft", user_id: 999,
      comments_attributes: [
        { body: "hi", "_destroy" => "0" },
        { "id" => "1", body: "edited", commentable_id: 42, commentable_type: "Post" }
      ]
    }
  )
  permitted = params.require(:article).permit(:title, :content, comments_attributes: [:id, :commenter, :body])
  h = permitted.to_h
  over_permitted_top = h.key?("user_id") || h.key?(:user_id)
  comments = h["comments_attributes"] || h[:comments_attributes] || []
  comments = comments.is_a?(Hash) ? comments.values : comments
  over_permitted_nested = comments.any? { |c| c.key?("commentable_id") || c.key?(:commentable_id) }
  has_title = h.key?("title") || h.key?(:title)
  ok = has_title && !over_permitted_top && !over_permitted_nested
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: has_title=#{has_title} over_permitted_top(user_id)=#{over_permitted_top} over_permitted_nested(commentable_id)=#{over_permitted_nested} got=#{h.inspect}"
rescue ActionController::UnpermittedParameters => e
  puts "RESULT: FAIL: unpermitted params raised: #{e.message}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
