# frozen_string_literal: true

# Tests RSpec pour lib/scansion.rb + lib/scansion/cli.rb (point d'entrée et
# CLI du gem scansion).

require_relative "../lib/scansion"

RSpec.describe Scansion do
  describe "bibliothèque sans effets de bord" do
    it "se require sans toucher à ARGV (Scansion.main n'est appelé que as script)" do
      # si le CLI tournait au require, l OptionParser lèverait InvalidOption
      expect(defined?(Scansion.main)).to eq("method")
    end
  end

end
