# Quick Feature Module

```
internal/modules/<feature>/
  domain/
    <entity>.go        Entity struct + constructor + business methods (pure Go, no frameworks)
    errors.go          Sentinel errors for this domain (ErrNotFound, ErrInvalidInput)
    repository.go      Repository interface (defined by domain, implemented by adapter)
  service/
    service.go         Service struct + New() constructor, depends on domain.Repository
    <action>.go        One file per business action (register.go, find.go, deactivate.go)
  handler/
    handler.go         Handler struct + New() + route registration
    <action>.go        One file per endpoint (register.go, find.go) — maps HTTP <-> service
    request.go         Request DTOs with validation tags
    response.go        Response DTOs — never expose domain entities directly
  repository/
    model.go           Unexported DB model with GORM tags — domain entity stays clean
    mapper.go          Mapping functions: model <-> domain entity
    <action>.go        One file per query (create.go, find_by_id.go, find_by_email.go)
```

Key rules:
- **File names = business actions**, folder = layer
- Domain has **zero** framework imports
- Service imports **only** domain
- Handler/repository import domain + their framework (Echo, GORM)
- Infrastructure code lives in `internal/infrastructure/`, never in business modules
- GORM tags live in `repository/model.go`, never on domain entities
