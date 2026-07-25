# frozen_string_literal: true

require 'test_helper'
require 'tempfile'

class ConstantCaptureTest < Minitest::Test
  def test_records_constants_defined_within_target_file
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['capture_constant', '.rb']) do |file|
      file.write("module CaptureHarnessConstant; end\n")
      file.flush

      capture.capture(file.path) { load file.path }
      assert_includes capture.constants_for(file.path), 'CaptureHarnessConstant'
    ensure
      cleanup_constant(:CaptureHarnessConstant)
    end
  end

  def test_ignores_constants_from_other_files
    capture = Rubycli::ConstantCapture.new
    fake_path = File.expand_path('../../lib/rubycli.rb', __FILE__)

    Tempfile.create(['capture_other', '.rb']) do |file|
      file.write("module CaptureForeignConstant; end\n")
      file.flush

      capture.capture(fake_path) { load file.path }
      assert_empty capture.constants_for(fake_path)
    ensure
      cleanup_constant(:CaptureForeignConstant)
    end
  end

  def test_records_class_assigned_to_constant
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['assigned_class', '.rb']) do |file|
      file.write("CaptureAssignedClass = Class.new do\n  def self.run; end\nend\n")
      file.flush

      capture.capture(file.path) { load file.path }

      assert_includes capture.constants_for(file.path), 'CaptureAssignedClass'
    ensure
      cleanup_constant(:CaptureAssignedClass)
    end
  end

  def test_records_module_assigned_to_constant
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['assigned_module', '.rb']) do |file|
      file.write("CaptureAssignedModule = Module.new do\n  def self.run; end\nend\n")
      file.flush

      capture.capture(file.path) { load file.path }

      assert_includes capture.constants_for(file.path), 'CaptureAssignedModule'
    ensure
      cleanup_constant(:CaptureAssignedModule)
    end
  end

  def test_records_assigned_alias_when_same_file_is_loaded_twice
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['assigned_alias', '.rb']) do |file|
      file.write(<<~RUBY)
        module CaptureAliasSource
          def self.run; end
        end
        CaptureAssignedAlias = CaptureAliasSource
      RUBY
      file.flush

      2.times do
        capture_io do
          capture.capture(file.path) { load file.path }
        end
        assert_includes capture.constants_for(file.path), 'CaptureAssignedAlias'
      end
    ensure
      cleanup_constant(:CaptureAssignedAlias)
      cleanup_constant(:CaptureAliasSource)
    end
  end

  def test_records_assigned_alias_after_source_file_is_edited
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['edited_assigned_alias', '.rb']) do |file|
      source = <<~RUBY
        module CaptureEditedAliasSource
          def self.run; end
        end
        CaptureEditedAssignedAlias = CaptureEditedAliasSource
      RUBY
      file.write(source)
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write("#{source}\n# harmless edit\n")
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      assert_includes capture.constants_for(file.path), 'CaptureEditedAssignedAlias'
    ensure
      cleanup_constant(:CaptureEditedAssignedAlias)
      cleanup_constant(:CaptureEditedAliasSource)
    end
  end

  def test_records_guarded_constant_after_source_file_is_edited
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['edited_guarded_constant', '.rb']) do |file|
      source = <<~RUBY
        CaptureGuardedRunner ||= Class.new do
          def self.run; end
        end
      RUBY
      file.write(source)
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write("#{source}\n# harmless edit\n")
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      assert_includes capture.constants_for(file.path), 'CaptureGuardedRunner'
    ensure
      cleanup_constant(:CaptureGuardedRunner)
    end
  end

  def test_retains_defined_guarded_alias_when_same_file_is_loaded_twice
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['defined_guarded_alias', '.rb']) do |file|
      file.write(<<~RUBY)
        module CaptureDefinedGuardedAliasSource
          def self.run; end
        end
        unless defined?(CaptureDefinedGuardedAssignedAlias)
          CaptureDefinedGuardedAssignedAlias = CaptureDefinedGuardedAliasSource
        end
      RUBY
      file.flush

      2.times do
        capture_io { capture.capture(file.path) { load file.path } }
        assert_includes capture.constants_for(file.path), 'CaptureDefinedGuardedAssignedAlias'
      end
    ensure
      cleanup_constant(:CaptureDefinedGuardedAssignedAlias)
      cleanup_constant(:CaptureDefinedGuardedAliasSource)
    end
  end

  def test_does_not_retain_assigned_alias_removed_from_edited_source
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['removed_assigned_alias', '.rb']) do |file|
      file.write(<<~RUBY)
        module CaptureRemovedAliasSource
          def self.run; end
        end
        CaptureRemovedAssignedAlias = CaptureRemovedAliasSource
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write(<<~RUBY)
        module CaptureRemovedAliasSource
          def self.run; end
        end
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      assert_includes capture.constants_for(file.path), 'CaptureRemovedAliasSource'
      refute_includes capture.constants_for(file.path), 'CaptureRemovedAssignedAlias'
    ensure
      cleanup_constant(:CaptureRemovedAssignedAlias)
      cleanup_constant(:CaptureRemovedAliasSource)
    end
  end

  def test_records_qualified_and_absolute_aliases_after_source_file_is_edited
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['edited_qualified_aliases', '.rb']) do |file|
      source = <<~RUBY
        module CaptureQualifiedAliasOwner; end
        module CaptureQualifiedAliasSource
          def self.run; end
        end
        CaptureQualifiedAliasOwner::Runner = CaptureQualifiedAliasSource
        ::CaptureAbsoluteAssignedAlias = CaptureQualifiedAliasSource
      RUBY
      file.write(source)
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write("#{source}\n# harmless edit\n")
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      assert_includes capture.constants_for(file.path), 'CaptureQualifiedAliasOwner::Runner'
      assert_includes capture.constants_for(file.path), 'CaptureAbsoluteAssignedAlias'
    ensure
      if Object.const_defined?(:CaptureQualifiedAliasOwner)
        owner = Object.const_get(:CaptureQualifiedAliasOwner)
        owner.send(:remove_const, :Runner) if owner.const_defined?(:Runner, false)
      end
      cleanup_constant(:CaptureAbsoluteAssignedAlias)
      cleanup_constant(:CaptureQualifiedAliasOwner)
      cleanup_constant(:CaptureQualifiedAliasSource)
    end
  end

  def test_records_multiple_assigned_aliases_after_source_file_is_edited
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['edited_multiple_aliases', '.rb']) do |file|
      source = <<~RUBY
        module CaptureMultipleAliasSource
          def self.run; end
        end
        CaptureMultipleAliasOne, CaptureMultipleAliasTwo = CaptureMultipleAliasSource, CaptureMultipleAliasSource
      RUBY
      file.write(source)
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write("#{source}\n# harmless edit\n")
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      assert_includes capture.constants_for(file.path), 'CaptureMultipleAliasOne'
      assert_includes capture.constants_for(file.path), 'CaptureMultipleAliasTwo'
    ensure
      cleanup_constant(:CaptureMultipleAliasOne)
      cleanup_constant(:CaptureMultipleAliasTwo)
      cleanup_constant(:CaptureMultipleAliasSource)
    end
  end

  def test_does_not_retain_alias_when_edited_assignment_is_not_executed
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['skipped_edited_alias', '.rb']) do |file|
      file.write(<<~RUBY)
        module CaptureSkippedAliasSource
          def self.run; end
        end
        CaptureSkippedAssignedAlias = CaptureSkippedAliasSource
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write(<<~RUBY)
        module CaptureSkippedAliasSource
          def self.run; end
        end
        if false
          CaptureSkippedAssignedAlias = CaptureSkippedAliasSource
        end
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      refute_includes capture.constants_for(file.path), 'CaptureSkippedAssignedAlias'
    ensure
      cleanup_constant(:CaptureSkippedAssignedAlias)
      cleanup_constant(:CaptureSkippedAliasSource)
    end
  end

  def test_retains_multiline_conditional_alias_when_assignment_executes_after_edit
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['executed_conditional_edited_alias', '.rb']) do |file|
      source = <<~RUBY
        module CaptureExecutedConditionalAliasSource
          def self.run; end
        end
        enabled = true
        if enabled
          CaptureExecutedConditionalAssignedAlias = CaptureExecutedConditionalAliasSource
        end
      RUBY
      file.write(source)
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write("#{source}\n# harmless edit\n")
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      assert_includes capture.constants_for(file.path), 'CaptureExecutedConditionalAssignedAlias'
    ensure
      cleanup_constant(:CaptureExecutedConditionalAssignedAlias)
      cleanup_constant(:CaptureExecutedConditionalAliasSource)
    end
  end

  def test_does_not_retain_multiline_conditional_alias_when_runtime_guard_changes
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['disabled_conditional_edited_alias', '.rb']) do |file|
      file.write(<<~RUBY)
        module CaptureDisabledConditionalAliasSource
          def self.run; end
        end
        enabled = true
        if enabled
          CaptureDisabledConditionalAssignedAlias = CaptureDisabledConditionalAliasSource
        end
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write(<<~RUBY)
        module CaptureDisabledConditionalAliasSource
          def self.run; end
        end
        enabled = false
        if enabled
          CaptureDisabledConditionalAssignedAlias = CaptureDisabledConditionalAliasSource
        end
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      refute_includes capture.constants_for(file.path), 'CaptureDisabledConditionalAssignedAlias'
    ensure
      cleanup_constant(:CaptureDisabledConditionalAssignedAlias)
      cleanup_constant(:CaptureDisabledConditionalAliasSource)
    end
  end

  def test_does_not_retain_alias_from_inactive_branch_when_source_is_unchanged
    capture = Rubycli::ConstantCapture.new
    previous_mode = ENV['RUBYCLI_CAPTURE_MODE']
    Tempfile.create(['unchanged_dynamic_alias', '.rb']) do |file|
      file.write(<<~RUBY)
        module CaptureDynamicAliasSource
          def self.run; end
        end
        if ENV['RUBYCLI_CAPTURE_MODE'] == 'a'
          CaptureDynamicAliasA = CaptureDynamicAliasSource
        else
          CaptureDynamicAliasB = CaptureDynamicAliasSource
        end
      RUBY
      file.flush

      ENV['RUBYCLI_CAPTURE_MODE'] = 'a'
      capture_io { capture.capture(file.path) { load file.path } }
      assert_includes capture.constants_for(file.path), 'CaptureDynamicAliasA'

      ENV['RUBYCLI_CAPTURE_MODE'] = 'b'
      capture_io { capture.capture(file.path) { load file.path } }

      refute_includes capture.constants_for(file.path), 'CaptureDynamicAliasA'
      assert_includes capture.constants_for(file.path), 'CaptureDynamicAliasB'
    ensure
      ENV['RUBYCLI_CAPTURE_MODE'] = previous_mode
      cleanup_constant(:CaptureDynamicAliasA)
      cleanup_constant(:CaptureDynamicAliasB)
      cleanup_constant(:CaptureDynamicAliasSource)
    end
  end

  def test_does_not_retain_alias_when_edited_assignment_is_short_circuited
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['short_circuited_edited_alias', '.rb']) do |file|
      file.write(<<~RUBY)
        module CaptureShortCircuitedAliasSource
          def self.run; end
        end
        CaptureShortCircuitedAssignedAlias = CaptureShortCircuitedAliasSource
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write(<<~RUBY)
        module CaptureShortCircuitedAliasSource
          def self.run; end
        end
        false && (CaptureShortCircuitedAssignedAlias = CaptureShortCircuitedAliasSource)
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      refute_includes capture.constants_for(file.path), 'CaptureShortCircuitedAssignedAlias'
    ensure
      cleanup_constant(:CaptureShortCircuitedAssignedAlias)
      cleanup_constant(:CaptureShortCircuitedAliasSource)
    end
  end

  def test_does_not_retain_alias_when_edited_postfix_assignment_is_skipped
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['postfix_skipped_edited_alias', '.rb']) do |file|
      file.write(<<~RUBY)
        module CapturePostfixSkippedAliasSource
          def self.run; end
        end
        CapturePostfixSkippedAssignedAlias = CapturePostfixSkippedAliasSource
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write(<<~RUBY)
        module CapturePostfixSkippedAliasSource
          def self.run; end
        end
        CapturePostfixSkippedAssignedAlias = CapturePostfixSkippedAliasSource if false
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      refute_includes capture.constants_for(file.path), 'CapturePostfixSkippedAssignedAlias'
    ensure
      cleanup_constant(:CapturePostfixSkippedAssignedAlias)
      cleanup_constant(:CapturePostfixSkippedAliasSource)
    end
  end

  def test_retains_alias_when_edited_postfix_assignment_executes
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['postfix_executed_edited_alias', '.rb']) do |file|
      source = <<~RUBY
        module CapturePostfixExecutedAliasSource
          def self.run; end
        end
        CapturePostfixExecutedAssignedAlias = CapturePostfixExecutedAliasSource if true
      RUBY
      file.write(source)
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write("#{source}\n# harmless edit\n")
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      assert_includes capture.constants_for(file.path), 'CapturePostfixExecutedAssignedAlias'
    ensure
      cleanup_constant(:CapturePostfixExecutedAssignedAlias)
      cleanup_constant(:CapturePostfixExecutedAliasSource)
    end
  end

  def test_records_const_set_alias_after_source_file_is_edited
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['edited_const_set_alias', '.rb']) do |file|
      source = <<~RUBY
        module CaptureConstSetAliasSource
          def self.run; end
        end
        Object.const_set(:CaptureConstSetAssignedAlias, CaptureConstSetAliasSource)
      RUBY
      file.write(source)
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write("#{source}\n# harmless edit\n")
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      assert_includes capture.constants_for(file.path), 'CaptureConstSetAssignedAlias'
    ensure
      cleanup_constant(:CaptureConstSetAssignedAlias)
      cleanup_constant(:CaptureConstSetAliasSource)
    end
  end

  def test_retains_guarded_const_set_alias_after_source_file_is_edited
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['edited_guarded_const_set_alias', '.rb']) do |file|
      source = <<~RUBY
        module CaptureGuardedConstSetAliasSource
          def self.run; end
        end
        unless Object.const_defined?(:CaptureGuardedConstSetAssignedAlias, false)
          Object.const_set(:CaptureGuardedConstSetAssignedAlias, CaptureGuardedConstSetAliasSource)
        end
      RUBY
      file.write(source)
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write("#{source}\n# harmless edit\n")
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      assert_includes capture.constants_for(file.path), 'CaptureGuardedConstSetAssignedAlias'
    ensure
      cleanup_constant(:CaptureGuardedConstSetAssignedAlias)
      cleanup_constant(:CaptureGuardedConstSetAliasSource)
    end
  end

  def test_does_not_retain_const_set_moved_into_uninvoked_method
    capture = Rubycli::ConstantCapture.new
    Tempfile.create(['deferred_const_set_alias', '.rb']) do |file|
      file.write(<<~RUBY)
        module CaptureDeferredConstSetAliasSource
          def self.run; end
        end
        Object.const_set(:CaptureDeferredConstSetAssignedAlias, CaptureDeferredConstSetAliasSource)
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }
      file.rewind
      file.truncate(0)
      file.write(<<~RUBY)
        module CaptureDeferredConstSetAliasSource
          def self.run; end
        end
        def capture_install_deferred_alias
          Object.const_set(:CaptureDeferredConstSetAssignedAlias, CaptureDeferredConstSetAliasSource)
        end
      RUBY
      file.flush

      capture_io { capture.capture(file.path) { load file.path } }

      refute_includes capture.constants_for(file.path), 'CaptureDeferredConstSetAssignedAlias'
    ensure
      Object.send(:remove_method, :capture_install_deferred_alias) if Object.private_method_defined?(:capture_install_deferred_alias)
      cleanup_constant(:CaptureDeferredConstSetAssignedAlias)
      cleanup_constant(:CaptureDeferredConstSetAliasSource)
    end
  end

  def test_does_not_retain_postfix_const_set_when_runtime_guard_changes
    capture = Rubycli::ConstantCapture.new
    previous_mode = ENV['RUBYCLI_CONST_SET_MODE']
    Tempfile.create(['postfix_const_set_alias', '.rb']) do |file|
      file.write(<<~RUBY)
        module CapturePostfixConstSetAliasSource
          def self.run; end
        end
        Object.const_set(:CapturePostfixConstSetAssignedAlias, CapturePostfixConstSetAliasSource) if ENV['RUBYCLI_CONST_SET_MODE'] == 'on'
      RUBY
      file.flush

      ENV['RUBYCLI_CONST_SET_MODE'] = 'on'
      capture_io { capture.capture(file.path) { load file.path } }
      assert_includes capture.constants_for(file.path), 'CapturePostfixConstSetAssignedAlias'

      ENV['RUBYCLI_CONST_SET_MODE'] = 'off'
      capture_io { capture.capture(file.path) { load file.path } }

      refute_includes capture.constants_for(file.path), 'CapturePostfixConstSetAssignedAlias'
    ensure
      ENV['RUBYCLI_CONST_SET_MODE'] = previous_mode
      cleanup_constant(:CapturePostfixConstSetAssignedAlias)
      cleanup_constant(:CapturePostfixConstSetAliasSource)
    end
  end

  private

  def cleanup_constant(name)
    Object.send(:remove_const, name) if Object.const_defined?(name)
  end
end
