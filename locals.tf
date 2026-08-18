locals {
  resource_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Experience  = "Digital Terrarium"
    Repository  = "github.com/jean-tmk/digital-terrarium"
  }

  mime_types = {
    ".html" = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "text/javascript; charset=utf-8"
    ".json" = "application/json"
    ".svg"  = "image/svg+xml"
    ".png"  = "image/png"
    ".webp" = "image/webp"
    ".ico"  = "image/x-icon"
    ".txt"  = "text/plain; charset=utf-8"
  }

  static_files = {
    for path in fileset(var.site_source_dir, "**") :
    path => {
      absolute_path = "${var.site_source_dir}/${path}"
      extension     = length(regexall("\\.[^.]+$", path)) > 0 ? regex("\\.[^.]+$", path) : ""
      cache_control = endswith(path, ".html") ? "no-cache" : "public, max-age=31536000, immutable"
    }
    if !startswith(path, ".git/")
    && !startswith(path, ".github/")
    && !startswith(path, ".terraform/")
    && !startswith(path, "api/")
    && !startswith(path, "ecology/")
    && !startswith(path, "modules/")
    && !startswith(path, "examples/")
    && !endswith(path, ".tf")
    && !endswith(path, ".tfstate")
    && !endswith(path, ".md")
  }

  api_routes = {
    "GET /health"                = "health"
    "GET /habitats/{id}"         = "read"
    "PUT /habitats/{id}"         = "write"
    "POST /habitats/{id}/cycle"  = "cycle"
    "DELETE /habitats/{id}"      = "delete"
  }

  cors_headers = [
    "content-type",
    "if-match",
    "x-terrarium-seed",
    "x-request-id"
  ]
}
