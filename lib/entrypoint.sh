#!/bin/sh

set -e

gem install rubocop -v 1.51.0
gem install rubocop-packaging -v 0.5.2
gem install rubocop-rspec -v 2.22.0
gem install rubocop-performance -v 1.18.0
gem install rubocop-rails -v 2.20.2


ruby /action/lib/index.rb
