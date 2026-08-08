class PostsController < ApplicationController
  def publish
    @post = Post.find(params[:id])
    @post.update(status: "published")
    redirect_to @post, notice: "Post was successfully published."
  end
end
