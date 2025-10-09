# Appsmith

- Source: https://github.com/appsmithorg/appsmith
- License: [Apache2](https://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: Lowcoder, Retool, Budibase, ToolJet.

## Features

- **Low-Code Platform**: Build internal tools and dashboards with drag-and-drop interface
- **Database Integrations**: Connect to PostgreSQL, MySQL, MongoDB, REST APIs, and more
- **Custom Widgets**: Pre-built UI components for tables, forms, charts, and maps
- **JavaScript Support**: Add custom logic and data transformations
- **Role-Based Access**: User authentication and permission management
- **Git Integration**: Version control and collaborative development workflows

## VM

I had to up the VM CPU type from `KVM` to `host` in order to fix some errors I saw starting this container. CPU compatibility issues when running MongoDB within the container; could potentially be fixed by hosting MongoDB separately.
