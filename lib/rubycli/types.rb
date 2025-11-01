module Rubycli
  OptionDefinition = Struct.new(
    :keyword, :long, :short, :value_name, :types, :description, :requires_value,
    :boolean_flag, :optional_value, :default_value, :inline_type_annotation,
    :inline_type_text, :doc_format,
    keyword_init: true
  )

  PositionalDefinition = Struct.new(
    :placeholder, :label, :types, :description, :param_name, :default_value,
    :inline_type_annotation, :inline_type_text, :doc_format,
    keyword_init: true
  )

  ReturnDefinition = Struct.new(:types, :description, keyword_init: true)
end
