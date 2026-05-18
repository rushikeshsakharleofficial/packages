# Package Repository

Package repository for [rushikeshsakharleofficial](https://github.com/rushikeshsakharleofficial) tools.
Hosted at: `https://rushikeshsakharleofficial.github.io/packages/`

**Latest version: v1.1.1**

---

## code-outline-graph-go

Go code indexing and search MCP server.

### Debian / Ubuntu (apt)

```bash
echo "deb [trusted=yes arch=amd64] https://rushikeshsakharleofficial.github.io/packages/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/rushikesh.list
sudo apt update
sudo apt install code-outline-graph-go
```

### RHEL / Fedora / CentOS (dnf/yum)

```bash
sudo curl -fsSL https://rushikeshsakharleofficial.github.io/packages/rpm/rushikesh.repo \
  -o /etc/yum.repos.d/rushikesh.repo
sudo dnf install code-outline-graph-go
# or: sudo yum install code-outline-graph-go
```

### openSUSE (zypper)

```bash
sudo zypper addrepo https://rushikeshsakharleofficial.github.io/packages/rpm/rushikesh.repo
sudo zypper install code-outline-graph-go
```

### Alpine Linux (apk)

```bash
echo "https://rushikeshsakharleofficial.github.io/packages/apk/edge/main" \
  | sudo tee -a /etc/apk/repositories
sudo apk update --allow-untrusted
sudo apk add code-outline-graph-go --allow-untrusted
```

### Any platform (install script)

```bash
curl -fsSL https://raw.githubusercontent.com/rushikeshsakharleofficial/gocode-outline-graph/main/install.sh | bash
```
