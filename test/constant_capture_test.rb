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

  private

  def cleanup_constant(name)
    Object.send(:remove_const, name) if Object.const_defined?(name)
  end
end
