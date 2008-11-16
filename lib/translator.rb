require 'rubygems'
require 'parse_tree'
require 'ruby2ruby'

def translate(block)
  sexp = Sexp.from_array(block.to_sexp)
  page_dvar = sexp[1].last
  sexp = PageExtractor.new(page_dvar).process(s(:block, sexp.last))
  sexp = JSTranslator.new(page_dvar).process(sexp)
  sexp = PageWrapper.new.process(sexp)
  RubyToRuby.new.process(sexp)
end

def str(string)
  s(:str, string.to_s)
end

def dstr(*args)
  s(:dstr, *args)
end

def tricide?(*args)
  raise Exception if args.any? { |arg| arg == true } and args.any? { |arg| arg == false }

  if args.all? { |arg| arg == :maybe }
    false
  else
    args.any? { |arg| arg == true }
  end
end

def extract_name(global)
  global.to_s[1..-1]
end

class PageExtractor < SexpProcessor

  def initialize(page_variable)
    super()
    self.require_empty = false
    @page = page_variable
    @counter = 0
  end

  def has_gvar?(sexp)
    case sexp.first
    when :gvar
      true
    when :call
      has_gvar?(sexp[1])
    when :fcall
      has_gvar?(sexp[4])
    when :array
      sexp.body.any? { |e| has_gvar?(e) }
    else
      false
    end
  end

  def how_to_process(sexp)
    if sexp.first == :gvar
      :translate
    elsif has_gvar?(sexp)
      :extract
    else
      :ignore
    end
  end

  def translate_gvars(sexp)
    s(:array, *sexp[1..-1].map { |e| e.first == :gvar ? s(:lit, extract_name(e.last).to_sym) : e })
  end

  def extract_asgn_and_args(sexp)
    asgn = nil
    args = sexp[1..-1].map do |e|
      if has_gvar?(e)
        id = "mothertongue_#{@counter += 1}".to_sym
        asgn = s(:gasgn, "$#{id}".to_sym, e)
        s(:lit, id)
      else
        e
      end
    end

    [asgn, s(:array, *args)]
  end

  def process_call(sexp)
    if sexp[1] == s(:dvar, @page)
      case sexp[2]
      when :insert_html
        case how_to_process(sexp[3][2])
        when :translate
          s(:call, s(:dvar, @page), :insert_html, translate_gvars(sexp[3]))
        when :extract
          asgn, args = extract_asgn_and_args(sexp[3])
          s(:block,
            asgn,
            s(:call, s(:dvar, @page), :insert_html, args))
        when :ignore
          sexp
        end
      end
    else
      sexp
    end
  end

end


class JSTranslator < SexpProcessor

  def initialize(page_variable)
    super()
    self.require_empty = false
    @context = []
    @translate_context = []
    @page = page_variable
  end

  def translate?(sexp)
    case sexp.first
    when :str, :lit
      :maybe
    when :gasgn, :gvar
      true
    when :dvar
      sexp.last != @page and @translate_context.any? { |e| e == true }
    when :dasgn_curr, :masgn
      @translate_context.any? { |e| e == true }
    when :fcall
      sexp.size == 3 and tricide? translate?(sexp.last)
    when :if, :attrasgn, :call, :while, :until, :iter, :return
      tricide? translate?(sexp[1])
    when :array, :block
      sexp[1..-1].any? { |exp| tricide? translate?(exp) }
    else
      false
    end
  end

  def process(sexp, force_translate = false)
    @context << sexp.first
    result = if force_translate or tricide?(translate?(sexp))
      @translate_context << true
      super(sexp)
    else
      @translate_context << false
      sexp
    end
    @context.delete_at -1
    @translate_context.delete_at -1
    result
  end

  def process_gasgn(sexp)
    dstr(extract_name(sexp[1]), str(" = "), process(sexp.last, true))
  end

  def process_attrasgn(sexp)
    dstr('', process(sexp[1]), str('.'), str(sexp[2].to_s.sub('=', '')), str(' = '), process(sexp.last.last, true))
  end

  def process_lit(sexp)
    str(sexp.last.to_s)
  end

  def process_str(sexp)
    str('"' + sexp.last + '"')
  end

  def process_hash(sexp)
    result = dstr('{ ')

    # FIXME there has to be a better way
    content = sexp[1..-1]
    if content.size > 0
      (0...(content.size-1)/2).each { |i| result << process(content[2*i], true);result << str(': ');result << process(content[2*i+1], true);result << str(', ') }
      result << process(content[-2], true);result << str(': ');result << process(content[-1], true)
    end

    result << str(' }')
  end

  def process_gvar(sexp)
    str(extract_name(sexp.last))
  end

  def process_dvar(sexp)
    str(sexp.last)
  end

  def process_ivar(sexp)
    s(:call, sexp, :to_json)
  end

  def process_lvar(sexp)
    s(:call, sexp, :to_json)
  end

  def process_dasgn_curr(sexp)
    str(sexp.last)
  end

  def process_masgn(sexp)
    dstr('', *process_array_body(sexp.last))
  end

  def process_vcall(sexp)
    s(:call, sexp, :to_json)
  end

  def process_fcall(sexp)
    dstr(sexp[1].to_s, str('('), *process_array_body(sexp.last)) << str(')')
  end

  def process_call(sexp)
    result = dstr('', process(sexp[1]), str('.'), str(sexp[2]))
    result << str('(') unless @context.include?(:attrasgn)
    if sexp.size == 4
      process_array_body(sexp.last).each { |arg| result << arg }
    end
    result << str(')') unless @context.include?(:attrasgn)
    result
  end

  def process_if(sexp)
    result = s(:block, dstr('if(', process(sexp[1]), str(') {')))
    result << process(sexp[2]) if sexp[2]
    if sexp[3]
      result << str('} else {')
      result << process(sexp[3])
    end
    result << str('}')
  end

  def process_return(sexp)
    dstr('return ', process(sexp[1]))
  end

  def process_while(sexp)
    result = s(:block, dstr('while(', process(sexp[1]), str(') {')))
    result << process(sexp[2]) if sexp[2]
    result << str('}')
  end

  def process_until(sexp)
    result = s(:block, dstr('while(!(', process(sexp[1]), str(')) {')))
    result << process(sexp[2]) if sexp[2]
    result << str('}')
  end

  def process_iter(sexp)
    header = dstr('$A(', process(sexp[1][1]), str(').'), str(sexp[1][2]), str('('))
    if sexp[1].size == 4
      process_array_body(sexp[1][3][1..-1]).each { |e| header << e }
      header << str(', ')
    end
    header << str('function(')
    header << process(sexp[2]) if sexp[2]
    header << str(') {')
    
    result = s(:block, header)
    result << process(sexp[3]) if sexp[3]
    result << str('})')
  end

  def process_array(sexp)
    dstr('[', *process_array_body(sexp)) << str(']')
  end

  def process_array_body(sexps)
    # FIXME not pretty
    result = []
    sexps[1...-1].each do |exp|
      result << process_or_wrap(exp)
      result << str(', ')
    end
    result << process_or_wrap(sexps[-1])
  end

  def process_or_wrap(sexp)
    translate?(sexp) ? process(sexp, true) : s(:call, sexp, :to_json)
  end

end

class PageWrapper < SexpProcessor

  def initialize
    super
    self.require_empty = false
  end

  def process_block(sexp)
    result = s(:block)
    sexp[1..-1].each do |exp|
      case exp.first
      when :str, :dstr, :block
        result << process(exp)
      else
        result << exp
      end
    end
    result
  end

  def process_str(sexp)
    s(:call, s(:dvar, :page), :<<, s(:array, sexp))
  end

  def process_dstr(sexp)
    s(:call, s(:dvar, :page), :<<, s(:array, sexp))
  end

end
