require 'test/unit'
require 'translator'

class Fixnum
  def to_json
    to_s
  end
end

class Array
  def to_json
    inspect
  end
end

class String
  def to_json
    '"' + self + '"'
  end
end

class Hash
  def to_json
    result = []
    each do |k, v|
      result << "#{k.to_json}: #{v.to_json}"
    end
    "{ #{result.join(', ')} }"
  end
end

class PageFaker

  def initialize
    @result = []
  end

  def <<(arg)
    @result << arg
  end

  def insert_html(position, div_id, options_for_render = {})
    @result << "new Insertion.#{position.to_s.capitalize}(#{div_id}, \"#{options_for_render[:text]}\");"
  end

  def result
    @result
  end

end

def assert_invariant(input)
  def sexp_dup(sexp)
    result = Sexp.new
    sexp.each do |e|
      if e.is_a?(Array)
        result << sexp_dup(e)
      else
        result << e
      end
    end
    result
  end

  assert_translates_to input, sexp_dup(input)
end

class FullStackTest < Test::Unit::TestCase

  def assert_translates_to(expected, setup = "", page_variable = 'page', &block)
    eval setup

    eval "#{page_variable} = PageFaker.new"
    eval translate(block)
    
    assert_equal expected, eval("#{page_variable}.result")
  end

  def test_variable_assignment
    assert_translates_to ['i = "string"'] do
      $i = 'string'
    end
  end

  def test_variable_array_assignment
    assert_translates_to ['i = [5]', 'j = [1, "string"]'], '@my_local_var = [5]' do
      $i = @my_local_var
      $j = [@my_local_var.size, 'string']
    end
  end

  def test_variable_hash_assignment
    assert_translates_to ['i = { 2: "string", "string": 1 }', 'j = { 3: 4, 5: my_var }'], '@my_local_var = { "string" => 1, 2 => "string" }' do
      $i = @my_local_var
      $j = { 3 => 4, 5 => $my_var }
    end
  end

  def test_variable_nested_array_assignment
    assert_translates_to ['j = [[5, [5], my_var], "string"]'], '@my_local_var = 5;@my_local_array = [5]' do
      $j = [[@my_local_var, @my_local_array, $my_var], 'string']
    end
  end

  def test_nested_assignment
    assert_translates_to ['window.location.href = "http://myawesomesite.com"'] do
      $window.location.href = 'http://myawesomesite.com'
    end
  end

  def test_function_call
    assert_translates_to ['my_func(my_var)'] do
      my_func $my_var
    end
  end

  def test_function_call_with_marshalling
    assert_translates_to ['my_func(my_var, 5)'], '@my_local_var = 5' do
      my_func $my_var, @my_local_var
    end
  end

  def test_method_call
    assert_translates_to ['my_obj.my_method(my_var)'] do
      $my_obj.my_method $my_var
    end
  end

  def test_nested_method_call
    assert_translates_to ['my_obj.my_method(my_obj.my_other_method(my_var, 5, my_var.other_method(5, "string")))'] do
      $my_obj.my_method $my_obj.my_other_method($my_var, 5, $my_var.other_method(5, 'string'))
    end
  end

  def test_method_call_with_marshalling
    assert_translates_to ['my_obj.my_method(5)'], "@my_local_var = 5" do
      $my_obj.my_method @my_local_var
    end
  end

  def test_ignore_local_calls
    assert_translates_to ['my_obj.my_method(5)'], "@my_local_var = 5" do
      @array = []
      @array << @my_local_var
      $my_obj.my_method @my_local_var
    end
  end

  def test_if_conditional
    assert_translates_to ['if(queue.is_full()) {', 'alert(translator.getErrorMessage("queue_full"))', '}'] do
      alert($translator.getErrorMessage('queue_full')) if $queue.is_full
    end
  end

  def test_unless_conditional
    assert_translates_to ['if(queue.empty()) {', '} else {', 'alert(queue.first())', '}'] do
      alert($queue.first) unless $queue.empty
    end
  end

  def test_multi_line_conditional
    assert_translates_to ['if(queue.is_full()) {', 'error_message = "queue full"', 'alert(error_message)', 'queue.empty()', '}'] do
      if $queue.is_full
        $error_message = 'queue full'
        alert($error_message)
        $queue.empty
      end
    end
  end

  def test_nested_conditional
    assert_translates_to ['if(queue.is_full()) {', 'error_message = "queue full"', 'if(queue.is_whiny()) {', 'alert(error_message)', '}', 'queue.empty()', '}'] do
      if $queue.is_full
        $error_message = 'queue full'
        alert($error_message) if $queue.is_whiny
        $queue.empty
      end
    end
  end

  def test_while
    assert_translates_to ['while(queue.empty()) {', 'queue.populate()', '}'] do
      $queue.populate while $queue.empty
    end
  end

  def test_multiline_while
    assert_translates_to ['while(queue.empty()) {', 'queue.populate()', 'queue.check(connection)', '}'] do
      while $queue.empty
        $queue.populate
        $queue.check $connection
      end
    end
  end

  def test_until
    assert_translates_to ['while(!(queue.is_full())) {', 'queue.populate()', '}'] do
      $queue.populate until $queue.is_full
    end
  end

  def test_multiline_until
    assert_translates_to ['while(!(queue.is_full())) {', 'queue.populate()', 'queue.check(connection)', '}'] do
      until $queue.is_full
        $queue.populate
        $queue.check $connection
      end
    end
  end

  def test_iteration
    assert_translates_to ['$A(queue.entries()).each(function(entry) {', 'entry.update()', '})'] do
      $queue.entries.each { |entry| entry.update }
    end
  end

  def test_iteration_with_argument
    assert_translates_to ['$A(queue.entries()).inject(0, function(entry) {', 'return entry.get_length()', '})'] do
      $queue.entries.inject(0) { |entry| return entry.get_length }
    end
  end

  def test_insertion_from_gvar
    assert_translates_to ['new Insertion.Bottom(div_id, "test");'] do |page|
      page.insert_html :bottom, $div_id, :text => "test"
    end
  end

  def test_insertion_from_gvar_method_call
    assert_translates_to ['mothertongue_1 = queue.div_id()', 'new Insertion.Bottom(mothertongue_1, "test");'] do |page|
      page.insert_html :bottom, $queue.div_id(), :text => "test"
    end
  end

  def test_insertion_from_gvar_with_non_standard_page_variable
    assert_translates_to ['new Insertion.Bottom(div_id, "test");'], '', 'imsick' do |imsick|
      imsick.insert_html :bottom, $div_id, :text => "test"
    end
  end

end

class TricideTest < Test::Unit::TestCase

  def test_all_true
    assert tricide?(true, true)
  end

  def test_all_false
    assert !tricide?(false, false)
  end

  def test_maybe_and_true
    assert tricide?(:maybe, true)
  end

  def test_maybe_and_false
    assert !tricide?(:maybe, false)
  end

  def test_maybe
    assert !tricide?(:maybe)
  end

  def test_multiple_maybe
    assert !tricide?(:maybe, :maybe)
  end

  def test_conflicting_will_raise_exception
    assert_raise(Exception) { tricide?(true, false) }
  end

  def test_conflicting_with_maybe_will_raise_exception
    assert_raise(Exception) { tricide?(true, false, :maybe) }
  end

end

class PageExtractorTest < Test::Unit::TestCase

  def assert_translates_to(expect, input)
    assert_equal expect, PageExtractor.new(:page).process(input)
  end

  def test_invariant_expressions
    invariants = []
    invariants << s(:call, s(:dvar, :page), :insert_html, s(:array, s(:lit, :bottom), str('div_id'), s(:hash, s(:lit, :text), str('text'))))

    invariants.each do |invariant|
      assert_invariant invariant
    end
  end

  def test_change_gvar_to_symbol_for_insert_html
    input = s(:call, s(:dvar, :page), :insert_html, s(:array, s(:lit, :bottom), s(:gvar, :$div_id), s(:hash, s(:lit, :text), str('text'))))
    output = s(:call, s(:dvar, :page), :insert_html, s(:array, s(:lit, :bottom), s(:lit, :div_id), s(:hash, s(:lit, :text), str('text'))))
    assert_translates_to output, input
  end

  def test_extract_call_on_gvar_for_insert_html
    input = s(:call, s(:dvar, :page), :insert_html, s(:array, s(:lit, :bottom), s(:call, s(:gvar, :$my_obj), :get_div_id), s(:hash, s(:lit, :text), str('text'))))
    output = s(:block,
                s(:gasgn, :$mothertongue_1, s(:call, s(:gvar, :$my_obj), :get_div_id)),
                s(:call, s(:dvar, :page), :insert_html, s(:array, s(:lit, :bottom), s(:lit, :mothertongue_1), s(:hash, s(:lit, :text), str('text')))))
    assert_translates_to output, input
  end

  def test_extract_multiple_call_on_gvar_for_insert_html
    input = s(:block,
               s(:call, s(:dvar, :page), :insert_html, s(:array, s(:lit, :bottom), s(:call, s(:gvar, :$my_obj), :get_div_id), s(:hash, s(:lit, :text), str('text')))),
               s(:call, s(:dvar, :page), :insert_html, s(:array, s(:lit, :bottom), s(:call, s(:gvar, :$my_obj), :get_div_id), s(:hash, s(:lit, :text), str('text')))))
    output = s(:block,
               s(:block,
                 s(:gasgn, :$mothertongue_1, s(:call, s(:gvar, :$my_obj), :get_div_id)),
                 s(:call, s(:dvar, :page), :insert_html, s(:array, s(:lit, :bottom), s(:lit, :mothertongue_1), s(:hash, s(:lit, :text), str('text'))))),
               s(:block,
                 s(:gasgn, :$mothertongue_2, s(:call, s(:gvar, :$my_obj), :get_div_id)),
                 s(:call, s(:dvar, :page), :insert_html, s(:array, s(:lit, :bottom), s(:lit, :mothertongue_2), s(:hash, s(:lit, :text), str('text'))))))
    assert_translates_to output, input
  end

end

class TranslatorTest < Test::Unit::TestCase

  def assert_translates_to(expect, input)
    assert_equal expect, JSTranslator.new(:page).process(input)
  end

  def test_invariant_assignments
    invariants = []
    invariants << s(:iasgn, :@i, s(:lit, 5))
    invariants << s(:lasgn, :@i, s(:lit, 5))
    invariants << s(:attrasgn, s(:vcall, :object), :attribute=, s(:array, str('string')))
    invariants << s(:attrasgn, s(:call, s(:ivar, :@object), :dementer_violation), :attribute=, s(:array, str('string')))

    invariants.each do |invariant|
      assert_invariant invariant
    end
  end

  def test_invariant_function_calls
    invariants = []
    invariants << s(:fcall, :my_ruby_func)
    invariants << s(:fcall, :my_ruby_func, s(:array, s(:ivar, :@my_var), s(:lit, :my_other_var)))
    invariants << s(:fcall, :my_ruby_func, s(:array, s(:lvar, :my_var), s(:str, 'some string')))
    invariants << s(:fcall, :my_ruby_func, s(:array, s(:vcall, :my_var)))
    invariants << s(:call, s(:vcall, :my_object), :my_method)
    invariants << s(:call, s(:lvar, :my_object), :my_method, s(:array, s(:lit, 5)))
    invariants << s(:call, s(:ivar, :@my_object), :my_method, s(:array, s(:vcall, :other_object)))
    invariants << s(:vcall, :my_method)
    invariants << s(:vcall, :my_method, s(:array, s(:lit, 5)))
    invariants << s(:vcall, :my_method, s(:array, s(:vcall, :other_object)))

    invariants.each do |invariant|
      assert_invariant invariant
    end
  end

  def test_invariant_conditionals
    invariants = []
    invariants << s(:if, s(:vcall, :decider), s(:vcall, :decide), nil)
    invariants << s(:if, s(:ivar, :@decider), s(:vcall, :decide), nil)
    invariants << s(:while, s(:vcall, :decider), s(:vcall, :decide), true)
    invariants << s(:while, s(:ivar, :@decider), s(:vcall, :decide), true)
    invariants << s(:until, s(:vcall, :decider), s(:vcall, :decide), true)
    invariants << s(:until, s(:ivar, :@decider), s(:vcall, :decide), true)

    invariants.each do |invariant|
      assert_invariant invariant
    end
  end

  def test_variable_global_assignment
    input = s(:gasgn, :$j, s(:gvar, :$i))
    output = s(:dstr, 'j', str(' = '), s(:str, 'i'))
    assert_translates_to output, input
  end

  def test_variable_integer_assignment
    input = s(:gasgn, :$i, s(:lit, 5))
    output = s(:dstr, 'i', str(' = '), s(:str, '5'))
    assert_translates_to output, input
  end

  def test_variable_string_assignment
    input = s(:gasgn, :$j, s(:str, "string"))
    output = s(:dstr, 'j', str(' = '), s(:str, '"string"'))
    assert_translates_to output, input
  end

  def test_variable_symbol_assignment
    input = s(:gasgn, :$j, s(:lit, :my_func))
    output = s(:dstr, 'j', str(' = '), s(:str, 'my_func'))
    assert_translates_to output, input
  end

  def test_variable_array_assignment_with_marshalling
    input = s(:gasgn, :$j, s(:array, s(:ivar, :@my_local_var)))
    output = s(:dstr, 'j', str(' = '), dstr('[', s(:call, s(:ivar, :@my_local_var), :to_json), str(']')))
    assert_translates_to output, input
  end

  def test_variable_array_assignment_with_string
    input = s(:gasgn, :$j, s(:array, str('string')))
    output = s(:dstr, 'j', str(' = '), dstr('[', str('"string"'), str(']')))
    assert_translates_to output, input
  end

  def test_variable_array_assignment_with_lit_and_marshalling
    input = s(:gasgn, :$j, s(:array, s(:call, s(:ivar, :@my_local_var), :my_method), s(:lit, :my_func)))
    output = s(:dstr, 'j', str(' = '), dstr('[', s(:call, s(:call, s(:ivar, :@my_local_var), :my_method), :to_json), str(', '), str('my_func'), str(']')))
    assert_translates_to output, input
  end

  def test_variable_hash_assignment_with_empty_hash
    input = s(:gasgn, :$j, s(:hash))
    output = s(:dstr, 'j', str(' = '), dstr('{ ', str(' }')))
    assert_translates_to output, input
  end

  def test_variable_hash_assignment_with_gvar
    input = s(:gasgn, :$j, s(:hash, s(:lit, 5), s(:gvar, :$my_var), s(:lit, :entry), s(:str, 'some string')))
    output = s(:dstr, 'j', str(' = '), dstr('{ ', str('5'), str(': '), str('my_var'), str(', '), str('entry'), str(': '), str('"some string"'), str(' }')))
    assert_translates_to output, input
  end

  def test_variable_multi_line_assignment
    input = s(:block,
              s(:gasgn, :$j, s(:array, s(:ivar, :@my_local_var))),
              s(:gasgn, :$j, s(:str, "string"))
             )
    output = s(:block,
                s(:dstr, 'j', str(' = '), dstr('[', s(:call, s(:ivar, :@my_local_var), :to_json), str(']'))),
                s(:dstr, 'j', str(' = '), s(:str, '"string"'))
              )
    assert_translates_to output, input
  end

  def test_nested_assignment
    input = s(:attrasgn, s(:call, s(:gvar, :$object), :nested), :attribute=, s(:array, str('string')))
    output = s(:dstr, '', dstr('', str('object'), str('.'), str('nested')), str('.'), str('attribute'), str(' = '), s(:str, '"string"'))
    assert_translates_to output, input
  end

  def test_function_call_with_global_argument
    input = s(:fcall, :my_func, s(:array, s(:gvar, :$my_var)))
    output = s(:dstr, 'my_func', str('('), str('my_var'), str(')'))
    assert_translates_to output, input
  end

  def test_function_call_with_multipe_global_argument
    input = s(:fcall, :my_func, s(:array, s(:gvar, :$my_var), s(:gvar, :$my_other_var)))
    output = s(:dstr, 'my_func', str('('), str('my_var'), str(', '), str('my_other_var'), str(')'))
    assert_translates_to output, input
  end

  def test_function_call_with_mixed_global_and_literal_arguments
    input = s(:fcall, :my_func, s(:array, s(:gvar, :$my_var), s(:lit, 5), str('some string')))
    output = s(:dstr, 'my_func', str('('), str('my_var'), str(', '), str('5'), str(', '), str('"some string"'), str(')'))
    assert_translates_to output, input
  end

  def test_method_call_without_arguments
    input = s(:call, s(:gvar, :$my_obj), :my_method)
    output = s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str(')'))
    assert_translates_to output, input
  end

  def test_method_call_with_string_argument
    input = s(:call, s(:gvar, :$my_obj), :my_method, s(:array, str('some string')))
    output = s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str('"some string"'), str(')'))
    assert_translates_to output, input
  end

  def test_method_call_with_global_argument
    input = s(:call, s(:gvar, :$my_obj), :my_method, s(:array, s(:gvar, :$my_var)))
    output = s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str('my_var'), str(')'))
    assert_translates_to output, input
  end

  def test_method_call_with_mixed_string_and_global_argument
    input = s(:call, s(:gvar, :$my_obj), :my_method, s(:array, str('some string'), s(:gvar, :$my_var)))
    output = s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str('"some string"'), str(', '), str('my_var'), str(')'))
    assert_translates_to output, input
  end

  def test_method_call_with_ivar_marshalling
    input = s(:call, s(:gvar, :$my_obj), :my_method, s(:array, s(:ivar, :@my_var)))
    output = s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), s(:call, s(:ivar, :@my_var), :to_json), str(')'))
    assert_translates_to output, input
  end

  def test_method_call_with_lvar_marshalling
    input = s(:call, s(:gvar, :$my_obj), :my_method, s(:array, s(:lvar, :my_var)))
    output = s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), s(:call, s(:lvar, :my_var), :to_json), str(')'))
    assert_translates_to output, input
  end

  def test_method_call_with_vcall_marshalling
    input = s(:call, s(:gvar, :$my_obj), :my_method, s(:array, s(:vcall, :@my_var)))
    output = s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), s(:call, s(:vcall, :@my_var), :to_json), str(')'))
    assert_translates_to output, input
  end

  def test_conditional_with_global_variable_and_empty_body
    input = s(:if, s(:gvar, :$decider), nil, nil)
    output = s(:block, s(:dstr, 'if(', str('decider'), str(') {')), str('}'))
    assert_translates_to output, input
  end

  def test_conditional_with_multi_line_body
    input = s(:if, s(:gvar, :$decider), 
                s(:block, 
                    s(:fcall, :my_func, s(:array, s(:gvar, :$my_var), s(:lit, 5), str('some string'))),
                    s(:call, s(:gvar, :$my_obj), :my_method)
                  ),
                nil)
    output = s(:block,
                s(:dstr, 'if(', str('decider'), str(') {')),
                s(:block,
                  s(:dstr, 'my_func', str('('), str('my_var'), str(', '), str('5'), str(', '), str('"some string"'), str(')')),
                  s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str(')'))
                ),
                str('}')
              )
    assert_translates_to output, input
  end

  def test_while_with_gvar_conditional_and_empty_body
    input = s(:while, s(:gvar, :$decider), nil, true)
    output = s(:block, dstr('while(', str('decider'), str(') {')), str('}'))
    assert_translates_to output, input
  end

  def test_while_with_method_conditional_and_single_instruction
    input = s(:while, s(:call, s(:gvar, :$my_obj), :decide), s(:call, s(:gvar, :$my_obj), :my_method), true)
    output = s(:block, dstr('while(', s(:dstr, '', str('my_obj'), str('.'), str('decide'), str('('), str(')')), str(') {')), 
                       s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str(')')),
                       str('}'))
    assert_translates_to output, input
  end

  def test_while_with_single_instruction
    input = s(:while, s(:gvar, :$decider), s(:call, s(:gvar, :$my_obj), :my_method), true)
    output = s(:block, dstr('while(', str('decider'), str(') {')), 
                       s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str(')')),
                       str('}'))
    assert_translates_to output, input
  end

  def test_while_with_multiple_instructions
    input = s(:while, s(:gvar, :$decider), s(:block, s(:call, s(:gvar, :$my_obj), :my_method), s(:call, s(:gvar, :$my_other_obj), :my_method)), true)
    output = s(:block, dstr('while(', str('decider'), str(') {')), 
                       s(:block, s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str(')')),
                                 s(:dstr, '', str('my_other_obj'), str('.'), str('my_method'), str('('), str(')'))),
                       str('}'))
    assert_translates_to output, input
  end

  def test_until_with_gvar_conditional_and_empty_body
    input = s(:until, s(:gvar, :$decider), nil, true)
    output = s(:block, dstr('while(!(', str('decider'), str(')) {')), str('}'))
    assert_translates_to output, input
  end

  def test_until_with_method_conditional_and_single_instruction
    input = s(:until, s(:call, s(:gvar, :$my_obj), :decide), s(:call, s(:gvar, :$my_obj), :my_method), true)
    output = s(:block, dstr('while(!(', s(:dstr, '', str('my_obj'), str('.'), str('decide'), str('('), str(')')), str(')) {')), 
                       s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str(')')),
                       str('}'))
    assert_translates_to output, input
  end

  def test_until_with_single_instruction
    input = s(:until, s(:gvar, :$decider), s(:call, s(:gvar, :$my_obj), :my_method), true)
    output = s(:block, dstr('while(!(', str('decider'), str(')) {')), 
                       s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str(')')),
                       str('}'))
    assert_translates_to output, input
  end

  def test_until_with_multiple_instructions
    input = s(:until, s(:gvar, :$decider), s(:block, s(:call, s(:gvar, :$my_obj), :my_method), s(:call, s(:gvar, :$my_other_obj), :my_method)), true)
    output = s(:block, dstr('while(!(', str('decider'), str(')) {')), 
                       s(:block, s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str(')')),
                                 s(:dstr, '', str('my_other_obj'), str('.'), str('my_method'), str('('), str(')'))),
                       str('}'))
    assert_translates_to output, input
  end

  def test_return_gvar
    input = s(:return, s(:gvar, :$my_var))
    output = dstr('return ', str('my_var'))
    assert_translates_to output, input
  end

  def test_return_method_call
    input = s(:return, s(:call, s(:gvar, :$my_var), :my_method))
    output = dstr('return ', s(:dstr, '', str('my_var'), str('.'), str('my_method'), str('('), str(')')))
    assert_translates_to output, input
  end

  def test_iteration_with_no_arguments_and_empty_body
    input = s(:iter, s(:call, s(:call, s(:gvar, :$my_obj), :my_iter), :each), nil)
    output = s(:block,
                dstr('$A(', s(:dstr, '', str('my_obj'), str('.'), str('my_iter'), str('('), str(')')), str(').'),
                     str('each'), str('('), str('function('), str(') {')),
                str('})')
              )
    assert_translates_to output, input
  end

  def test_iteration_with_single_arguments_and_empty_body
    input = s(:iter, s(:call, s(:call, s(:gvar, :$my_obj), :my_iter), :each), s(:dasgn_curr, :e))
    output = s(:block,
                dstr('$A(', s(:dstr, '', str('my_obj'), str('.'), str('my_iter'), str('('), str(')')), str(').'),
                     str('each'), str('('), str('function('), str('e'), str(') {')),
                str('})')
              )
    assert_translates_to output, input
  end

  def test_iteration_with_multiple_arguments_and_empty_body
    input = s(:iter, s(:call, s(:call, s(:gvar, :$my_obj), :my_iter), :each), s(:masgn, s(:array, s(:dasgn_curr, :k), s(:dasgn_curr, :v))))
    output = s(:block,
                dstr('$A(', s(:dstr, '', str('my_obj'), str('.'), str('my_iter'), str('('), str(')')), str(').'),
                     str('each'), str('('), str('function('), dstr('', str('k'), str(', '), str('v')), str(') {')),
                str('})')
              )
    assert_translates_to output, input
  end

  def test_iteration_with_single_argument_and_single_line_body
    input = s(:iter, s(:call, s(:call, s(:gvar, :$my_obj), :my_iter), :each), s(:dasgn_curr, :e), s(:call, s(:dvar, :e), :my_method))
    output = s(:block,
                dstr('$A(', s(:dstr, '', str('my_obj'), str('.'), str('my_iter'), str('('), str(')')), str(').'),
                     str('each'), str('('), str('function('), str('e'), str(') {')),
                s(:dstr, '', str('e'), str('.'), str('my_method'), str('('), str(')')),
                str('})')
              )
    assert_translates_to output, input
  end

  def test_iteration_with_multiple_argument_and_multiline_line_body
    input = s(:iter, s(:call, s(:call, s(:gvar, :$my_obj), :my_iter), :each),
                     s(:masgn, s(:array, s(:dasgn_curr, :k), s(:dasgn_curr, :v))),
                     s(:block, s(:call, s(:dvar, :k), :my_method),
                               s(:call, s(:dvar, :v), :my_other_method)))
    output = s(:block,
                dstr('$A(', s(:dstr, '', str('my_obj'), str('.'), str('my_iter'), str('('), str(')')), str(').'),
                     str('each'), str('('), str('function('), dstr('', str('k'), str(', '), str('v')), str(') {')),
                s(:block, s(:dstr, '', str('k'), str('.'), str('my_method'), str('('), str(')')),
                          s(:dstr, '', str('v'), str('.'), str('my_other_method'), str('('), str(')'))),
                str('})')
              )
    assert_translates_to output, input
  end

  def test_iteration_with_processor_argument
    input = s(:iter, s(:call, s(:call, s(:gvar, :$my_obj), :my_iter), :inject, s(:array, s(:lit, 0))),
                     s(:dasgn_curr, :e),
                     s(:return, s(:call, s(:dvar, :e), :my_method)))
    output = s(:block,
                dstr('$A(', s(:dstr, '', str('my_obj'), str('.'), str('my_iter'), str('('), str(')')), str(').'),
                     str('inject'), str('('), str('0'), str(', '), str('function('), str('e'), str(') {')),
                s(:dstr, 'return ', s(:dstr, '', str('e'), str('.'), str('my_method'), str('('), str(')'))),
                str('})')
              )
    assert_translates_to output, input
  end

end

class PageWrapperTest < Test::Unit::TestCase

  def assert_translates_to(expect, input)
    assert_equal expect, PageWrapper.new.process(input)
  end

  def test_wrap_str
    input = s(:str, 'test')
    output = s(:call, s(:dvar, :page), :<<, s(:array, s(:str, 'test')))

    assert_translates_to output, input
  end

  def test_wrap_dstr
    input = s(:dstr, 'test', s(:lit, 5))
    output = s(:call, s(:dvar, :page), :<<, s(:array, s(:dstr, 'test', s(:lit, 5))))

    assert_translates_to output, input
  end

  def test_wrap_block
    input = s(:block, s(:dstr, 'if(', str('decider'), str(') {')), str('}'))
    output = s(:block,
                  s(:call, s(:dvar, :page), :<<, s(:array, s(:dstr, 'if(', str('decider'), str(') {')))),
                  s(:call, s(:dvar, :page), :<<, s(:array, str('}')))
              )

    assert_translates_to output, input
  end

  def test_wrap_nested_block
    input = s(:block,
               s(:dstr, 'if(', str('decider'), str(') {')),
               s(:block,
                 s(:dstr, 'my_func', str('('), str('my_var'), str(', '), str('5'), str(', '), str('"some string"'), str(')')),
                 s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str(')'))
               ),
               str('}')
             )
    output = s(:block,
               s(:call, s(:dvar, :page), :<<, s(:array, s(:dstr, 'if(', str('decider'), str(') {')))),
               s(:block,
                 s(:call, s(:dvar, :page), :<<, s(:array, s(:dstr, 'my_func', str('('), str('my_var'), str(', '), str('5'), str(', '), str('"some string"'), str(')')))),
                 s(:call, s(:dvar, :page), :<<, s(:array, s(:dstr, '', str('my_obj'), str('.'), str('my_method'), str('('), str(')'))))
               ),
               s(:call, s(:dvar, :page), :<<, s(:array, str('}')))
             )

    assert_translates_to output, input
  end

end

