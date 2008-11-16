require File.expand_path(File.join(File.dirname(__FILE__), '../../../../config/environment.rb'))
require 'action_controller/test_process'
require 'test/unit'

class MothertongueTest < Test::Unit::TestCase

  def setup
    @controller = MothertongueController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
  end

  def test_render_text
    get :text
    assert_equal 'some text', @response.body
  end

  def test_render_update
    get :javascript
    assert_equal "try {\nnew Insertion.Bottom(queue_div, \"test\");\n} catch (e) { alert('RJS error:\\n\\n' + e.toString()); alert('new Insertion.Bottom(queue_div, \\\"test\\\");'); throw e }", @response.body
  end

end

class MothertongueController < ActionController::Base
  def javascript
    render :update do |page|
      page.insert_html :bottom, $queue_div, "test"
    end
  end

  def text
    render :text => "some text"
  end
end

