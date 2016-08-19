require 'jetspider/ast'
require 'jetspider/exception'

module JetSpider
  class CodeGenerator < AstVisitor
    def initialize(object_file)
      @object_file = object_file
      @asm = nil
    end

    def generate_object_file(ast)
      @compiling_toplevel = false
      ast.global_functions.each do |fun|
        compile_function fun
      end
      compile_toplevel ast
      @object_file
    end

    def compile_function(fun)
      open_asm_writer(fun.scope, fun.filename, fun.lineno) {
        visit fun.function_body.value
      }
    end

    def compile_toplevel(ast)
      open_asm_writer(ast.global_scope, ast.filename, ast.lineno) {
        @compiling_toplevel = true
        traverse_ast(ast)
        @compiling_toplevel = false
      }
    end

    def open_asm_writer(*unit_args)
      unit = @object_file.new_unit(*unit_args)
      @asm = Assembler.new(unit)
      yield
      @asm.stop
    ensure
      @asm = nil
    end

    #
    # Declarations & Statements
    #

    def visit_SourceElementsNode(node)
      node.value.each do |n|
        visit n
      end
    end

    def visit_ExpressionStatementNode(node)
      visit node.value
      pop_statement_value
    end

    def pop_statement_value
      if @compiling_toplevel
        @asm.popv
      else
        @asm.pop
      end
    end

    def visit_EmptyStatementNode(n)
      # We can silently remove
    end

    def visit_BlockNode(n)
      visit n.value
    end

    def visit_CommaNode(n)
      visit n.left
      @asm.pop
      visit n.value
    end

    #
    # Functions-related
    #

    def visit_FunctionCallNode(n)
      @asm.callgname n.value.value
      n.arguments.value.each{ |item| visit item }
      @asm.call n.arguments.value.size
    end

    def visit_FunctionDeclNode(n)
      unless @compiling_toplevel
        raise SemanticError, "nested function not implemented yet"
      end
      # Function declarations are compiled in other step,
      # we just ignore them while compiling toplevel.
    end

    def visit_FunctionExprNode(n) raise "FunctionExprNode not implemented"; end

    def visit_ReturnNode(n)
      visit n.value
      @asm.return
    end

    # These nodes should not be visited directly
    def visit_ArgumentsNode(n) raise "[FATAL] ArgumentsNode visited"; end
    def visit_FunctionBodyNode(n) raise "[FATAL] FunctionBodyNode visited"; end
    def visit_ParameterNode(n) raise "[FATAL] ParameterNode visited"; end

    #
    # Variables-related
    #

    def visit_ResolveNode(n)
      var = n.variable
      case
      when var.parameter?
        @asm.getarg n.variable.index
      when var.local?
        raise NotImplementedError, 'ResolveNode - local'
      when var.global?
        @asm.getgname var.name
      else
        raise "[FATAL] unsupported variable type for dereference: #{var.inspect}"
      end
    end

    def visit_OpEqualNode(n)
      raise NotImplementedError, 'OpEqualNode'
    end

    def visit_VarStatementNode(n)
      raise NotImplementedError, 'VarStatementNode'
    end

    def visit_VarDeclNode(n)
      raise NotImplementedError, 'VarDeclNode'
    end

    def visit_AssignExprNode(n)
      raise NotImplementedError, 'AssignExprNode'
    end

    # We do not support let, const, with
    def visit_ConstStatementNode(n) raise "ConstStatementNode not implemented"; end
    def visit_WithNode(n) raise "WithNode not implemented"; end

    def visit_OpPlusEqualNode(n) raise "OpPlusEqualNode not implemented"; end
    def visit_OpMinusEqualNode(n) raise "OpMinusEqualNode not implemented"; end
    def visit_OpMultiplyEqualNode(n) raise "OpMultiplyEqualNode not implemented"; end
    def visit_OpDivideEqualNode(n) raise "OpDivideEqualNode not implemented"; end
    def visit_OpModEqualNode(n) raise "OpModEqualNode not implemented"; end
    def visit_OpAndEqualNode(n) raise "OpAndEqualNode not implemented"; end
    def visit_OpOrEqualNode(n) raise "OpOrEqualNode not implemented"; end
    def visit_OpXOrEqualNode(n) raise "OpXOrEqualNode not implemented"; end
    def visit_OpLShiftEqualNode(n) raise "OpLShiftEqualNode not implemented"; end
    def visit_OpRShiftEqualNode(n) raise "OpRShiftEqualNode not implemented"; end
    def visit_OpURShiftEqualNode(n) raise "OpURShiftEqualNode not implemented"; end

    #
    # Control Structures
    #

    def visit_IfNode(n)
      raise NotImplementedError, 'IfNode'
    end

    def visit_ConditionalNode(n)
      visit n.conditions
      loc = @asm.lazy_location
      loc_end = @asm.lazy_location
      @asm.ifeq loc
      visit n.value
      @asm.goto loc_end
      @asm.fix_location loc
      visit n.else
      @asm.fix_location loc_end
    end

    def visit_WhileNode(n)
      old_loc_end = @loop_loc_end
      old_loc_first = @loop_loc_first

      @loop_loc_end = @asm.lazy_location
      @loop_loc_first = @asm.lazy_location

      @asm.goto @loop_loc_first

      loc_inside = @asm.location

      # inside block
      # block node -> source elements node -> nodes
      visit n.value

      # if query
      @asm.fix_location @loop_loc_first

      visit n.left
      @asm.ifeq @loop_loc_end
      # no loop
      @asm.goto loc_inside

      @asm.fix_location @loop_loc_end

      # recover loc
      @loop_loc_end = old_loc_end
      @loop_loc_first = old_loc_first
    end

    def visit_DoWhileNode(n)
      raise NotImplementedError, 'DoWhileNode'
    end

    def visit_ForNode(n)
      raise NotImplementedError, 'ForNode'
    end

    def visit_BreakNode(n)
      @asm.goto @loop_loc_end
    end

    def visit_ContinueNode(n)
      @asm.goto @loop_loc_first
    end

    def visit_SwitchNode(n) raise "SwitchNode not implemented"; end
    def visit_CaseClauseNode(n) raise "CaseClauseNode not implemented"; end
    def visit_CaseBlockNode(n) raise "CaseBlockNode not implemented"; end

    def visit_ForInNode(n) raise "ForInNode not implemented"; end
    def visit_InNode(n) raise "InNode not implemented"; end
    def visit_LabelNode(n) raise "LabelNode not implemented"; end

    # We do not support exceptions
    def visit_TryNode(n) raise "TryNode not implemented"; end
    def visit_ThrowNode(n) raise "ThrowNode not implemented"; end

    #
    # Compound Expressions
    #

    def visit_ParentheticalNode(n)
      visit n.value
    end

    def visit_AddNode(n)
      # add or num
      optimized = optimize_Add_Node(n)
      if is_NumberNode?(optimized)
        @asm.int8(optimized.value)
      else
        visit optimized.value
        visit optimized.left
        @asm.add
      end
    end

    # return numbernode or else
    def optimize_Add_Node(n)
      if is_ParentheticalNode?(n)
        return optimize_Add_Node(n.value)
      end

      if is_AddNode?(n)
        # 両辺が最適化された node
        optimized_value = optimize_Add_Node(n.value)
        optimized_left = optimize_Add_Node(n.left)
        if is_NumberNode?(optimized_value) and is_NumberNode?(optimized_left)
          return create_NumberNode(optimized_value.value + optimized_left.value)
        else
          # numbernode でなければそのまま返す
          return RKelly::Nodes::AddNode.new(optimized_value, optimized_left)
        end
      end

      # add, parenthetical 以外ならそのまま返す
      return n
    end

    def is_WhileNode?(n)
      return n.is_a?(RKelly::Nodes::WhileNode)
    end

    def is_NumberNode?(n)
      return n.is_a?(RKelly::Nodes::NumberNode)
    end

    # () で発生
    def is_ParentheticalNode?(n)
      return n.is_a?(RKelly::Nodes::ParentheticalNode)
    end

    def is_AddNode?(n)
      return n.is_a?(RKelly::Nodes::AddNode)
    end

    def visit_SubtractNode(n)
      visit n.left
      visit n.value
      @asm.sub
    end

    def self.simple_binary_op(node_class, insn_name)
      define_method(:"visit_#{node_class}") {|node|
        visit node.left
        visit node.value
        @asm.__send__(insn_name)
      }
    end

    simple_binary_op 'MultiplyNode', :mul
    simple_binary_op 'DivideNode', :div
    simple_binary_op 'ModulusNode', :mod

    def visit_UnaryPlusNode(n)
      visit n.value
    end

    def visit_UnaryMinusNode(n)
      if is_NumberNode?(n.value)
        visit create_NumberNode(-n.value.value)
      else
        visit n.value
        @asm.neg
      end
    end

    def create_NumberNode(number)
      RKelly::Nodes::NumberNode.new(number)
    end

    # push int8 or int32
    def push_number(number)
      if number == 1
        @asm.one
      elsif number < 2**7 and number >= -2**7
        @asm.int8(number)
      elsif number < 2**16 and number >= 0
        @asm.uint16(number)
      elsif number < 2**24 and number >= 0
        @asm.uint24(number)
      else
        @asm.int32(number)
      end
    end

    def visit_PrefixNode(n)
      raise "PrefixNode not implemented"
    end

    def visit_PostfixNode(n)
      raise "PostfixNode not implemented"
    end

    def visit_BitwiseNotNode(n) raise "BitwiseNotNode not implemented"; end
    def visit_BitAndNode(n) raise "BitAndNode not implemented"; end
    def visit_BitOrNode(n) raise "BitOrNode not implemented"; end
    def visit_BitXOrNode(n) raise "BitXOrNode not implemented"; end
    def visit_LeftShiftNode(n) raise "LeftShiftNode not implemented"; end
    def visit_RightShiftNode(n) raise "RightShiftNode not implemented"; end
    def visit_UnsignedRightShiftNode(n) raise "UnsignedRightShiftNode not implemented"; end

    def visit_TypeOfNode(n) raise "TypeOfNode not implemented"; end

    #
    # Comparison
    #

    simple_binary_op 'EqualNode', :eq
    simple_binary_op 'NotEqualNode', :ne
    simple_binary_op 'StrictEqualNode', :stricteq
    simple_binary_op 'NotStrictEqualNode', :strictne

    simple_binary_op 'GreaterNode', :gt
    simple_binary_op 'GreaterOrEqualNode', :ge
    simple_binary_op 'LessNode', :lt
    simple_binary_op 'LessOrEqualNode', :le

    simple_binary_op 'LogicalAndNode', :and
    simple_binary_op 'LogicalOrNode', :or

    def visit_LogicalNotNode(n) raise "LogicalNotNode not implemented"; end

    #
    # Object-related
    #

    def visit_NewExprNode(n)
      raise NotImplementedError, 'NewExprNode'
    end

    def visit_DotAccessorNode(n)
      raise NotImplementedError, 'DotAccessorNode'
    end

    def visit_BracketAccessorNode(n)
      raise NotImplementedError, 'BracketAccessorNode'
    end

    def visit_InstanceOfNode(n) raise "InstanceOfNode not implemented"; end
    def visit_AttrNode(n) raise "AttrNode not implemented"; end
    def visit_DeleteNode(n) raise "DeleteNode not implemented"; end
    def visit_PropertyNode(n) raise "PropertyNode not implemented"; end
    def visit_GetterPropertyNode(n) raise "GetterPropertyNode not implemented"; end
    def visit_SetterPropertyNode(n) raise "SetterPropertyNode not implemented"; end

    #
    # Primitive Expressions
    #

    def visit_NullNode(n)
      @asm.null
    end

    def visit_TrueNode(n)
      @asm.true
    end

    def visit_FalseNode(n)
      @asm.false
    end

    def visit_ThisNode(n)
      @asm.this
    end

    def visit_NumberNode(n)
      push_number(n.value)
    end

    def visit_StringNode(n)
      @asm.string eval n.value
    end

    def visit_ArrayNode(n) raise "ArrayNode not implemented"; end
    def visit_ElementNode(n) raise "ElementNode not implemented"; end

    def visit_RegexpNode(n) raise "RegexpNode not implemented"; end

    def visit_ObjectLiteralNode(n) raise "ObjectLiteralNode not implemented"; end

    def visit_VoidNode(n) raise "VoidNode not implemented"; end
  end
end
