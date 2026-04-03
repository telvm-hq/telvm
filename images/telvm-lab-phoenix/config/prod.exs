import Config

# Lab containers are probed by Docker DNS name from the companion; relax host checks.
config :telvm_lab, TelvmLabWeb.Endpoint, check_origin: false
