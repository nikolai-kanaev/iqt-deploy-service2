require 'erb'

class Morph
  module GetBinding
    def get_binding
      binding
    end
  end

  include Albacore::Task

  attr_accessor :template, :output
  attr_hash :settings

  def execute
    morph(@template, @output, @settings)
  end

  def morph(template_file, output_file, settings)
    template = File.read template_file

    vars = OpenStruct.new(settings)
    vars.extend GetBinding

    File.open(output_file, "w") do |file|
      puts "morph is generating '#{file.path}'"
      erb = ERB.new template, 0, "%<>"
      file.write(erb.result(vars.get_binding))
    end
  end
end