# Mothertongue

class Symbol
  def to_json
    to_s
  end
end

module MothertongueIntegration
  def render_with_mothertongue(options = nil, deprecated_status = nil, &block)
    if options == :update
      add_variables_to_assigns
      @template.send :evaluate_assigns

      page = generator = ActionView::Helpers::PrototypeHelper::JavaScriptGenerator.new(@template) { |page|  }
      eval translate(block)
      render_javascript(generator.to_s)
    else
      render_without_mothertongue options, deprecated_status, &block
    end
  end
end

module ActionController
  class Base
    include MothertongueIntegration
    alias_method_chain :render, :mothertongue
  end
end
