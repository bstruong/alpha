class PostsController < ApplicationController
  def publish
    @post = Post.find(params[:id])
    if @post.update(status: "published", published_at: Time.current)
      redirect_to @post, notice: "Post was successfully published."
    else
      redirect_to @post, alert: "Failed to publish post."
    end
  end
end
