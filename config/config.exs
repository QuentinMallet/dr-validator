# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Sample configuration:
#
#     config :logger, :console,
#       level: :info,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]
#

# Validator registry — maps app name strings to AppValidator modules.
# Each sub-app that provides a validator registers itself here.
# DrValidator.Apps.lookup/1 reads this at runtime and guards with
# Code.ensure_loaded?/1 so absent sub-apps return nil gracefully.
config :dr_validator, validators: %{
  "openbao" => DrValidator.Apps.Openbao.RestoreTest
}

import_config "#{config_env()}.exs"
