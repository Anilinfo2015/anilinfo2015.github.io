#!/bin/bash

# Script to dynamically generate index.html based on repository contents
# This script scans the repository for markdown files and generates a beautiful index.html

set -e

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$REPO_ROOT"

# Function to convert directory name to title case
to_title_case() {
    echo "$1" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1'
}

# Function to extract title from markdown file
get_md_title() {
    local file="$1"
    local title=""
    
    # Validate file exists and is readable
    if [ ! -r "$file" ]; then
        title=$(basename "$file" .md | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
        echo "$title"
        return
    fi
    
    # Try to get title from first h1 heading (supports both # and === style)
    title=$(grep -m1 "^# " "$file" 2>/dev/null | sed 's/^# //' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    # If no title found, fallback to filename converted to title case
    if [ -z "$title" ]; then
        title=$(basename "$file" .md | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
    fi
    
    # Ensure title is not empty
    if [ -z "$title" ]; then
        title="Untitled"
    fi
    
    echo "$title"
}

# Function to get file modification date
get_file_date() {
    local file="$1"
    local date=""
    
    # Try to get date from git history
    date=$(git log -1 --format="%ci" -- "$file" 2>/dev/null | cut -d' ' -f1)
    
    # Fallback to current date if git history not available
    if [ -z "$date" ]; then
        date=$(date +%Y-%m-%d)
    fi
    
    echo "$date"
}

# Function to extract a short excerpt from markdown file
get_md_excerpt() {
    local file="$1"
    local excerpt=""

    if [ ! -r "$file" ]; then
        echo ""
        return
    fi

    excerpt=$(awk '
        BEGIN {in_fm=0; in_code=0}
        NR==1 && $0 ~ /^---$/ {in_fm=1; next}
        in_fm && $0 ~ /^---$/ {in_fm=0; next}
        in_fm {next}
        $0 ~ /^```/ {in_code = !in_code; next}
        in_code {next}
        $0 ~ /^#/ {next}
        NF==0 {next}
        {print; exit}
    ' "$file" | sed -E 's/`([^`]+)`/\1/g; s/\[([^\]]+)\]\([^)]+\)/\1/g; s/\*\*([^*]+)\*\*/\1/g; s/\*([^*]+)\*/\1/g' | tr -d '\r')

    if [ -z "$excerpt" ]; then
        echo ""
        return
    fi

    if [ ${#excerpt} -gt 180 ]; then
        excerpt="${excerpt:0:177}..."
    fi

    echo "$excerpt"
}

# Function to estimate reading time (minutes)
get_read_time() {
    local file="$1"
    local words=0

    if [ -r "$file" ]; then
        words=$(awk '
            BEGIN {in_fm=0; in_code=0; count=0}
            NR==1 && $0 ~ /^---$/ {in_fm=1; next}
            in_fm && $0 ~ /^---$/ {in_fm=0; next}
            in_fm {next}
            $0 ~ /^```/ {in_code = !in_code; next}
            in_code {next}
            {count += NF}
            END {print count}
        ' "$file")
    fi

    if [ -z "$words" ] || [ "$words" -le 0 ]; then
        echo "1"
        return
    fi

    local minutes=$(( (words + 199) / 200 ))
    if [ "$minutes" -lt 1 ]; then
        minutes=1
    fi

    echo "$minutes"
}

# Collect all markdown files organized by directory
declare -A categories
declare -a all_files
declare -a file_dates

# Find all markdown files
while IFS= read -r -d '' file; do
    # Skip hidden files and directories
    [[ "$file" =~ ^\./\. ]] && continue
    [[ "$file" =~ ^\./_ ]] && continue
    # Skip non-content folders
    [[ "$file" =~ ^\./scripts/ ]] && continue
    [[ "$file" =~ ^\./assets/ ]] && continue
    [[ "$file" =~ ^\./node_modules/ ]] && continue
    
    # Get relative path without ./
    rel_path="${file#./}"
    
    # Get directory
    dir=$(dirname "$rel_path")
    
    # Get file info
    title=$(get_md_title "$file")
    date=$(get_file_date "$file")
    
    # Extract excerpt and reading time
    excerpt=$(get_md_excerpt "$file")
    read_time=$(get_read_time "$file")

    # Store file info
    all_files+=("$rel_path|$title|$date|$dir|$excerpt|$read_time")
    
    # Add to category
    if [ "$dir" = "." ]; then
        category="root"
    else
        category="$dir"
    fi
    
    if [ -z "${categories[$category]}" ]; then
        categories[$category]="$rel_path|$title|$date"
    else
        categories[$category]="${categories[$category]};;;$rel_path|$title|$date"
    fi
done < <(find . -name "*.md" -not -path "./.git/*" -not -path "./_*" -print0 | sort -z)

# Generate HTML content for categories
generate_category_html() {
    local category="$1"
    local files="$2"
    local category_title
    local category_id
    local icon_class
    
    if [ "$category" = "root" ]; then
        category_title="Getting Started"
        icon_class="fas fa-rocket"
    else
        category_title=$(to_title_case "$category")
        case "$category" in
            *design-patterns*) icon_class="fas fa-palette" ;;
            *architecture*) icon_class="fas fa-building" ;;
            *scalability*) icon_class="fas fa-chart-line" ;;
            *security*) icon_class="fas fa-shield-alt" ;;
            *database*) icon_class="fas fa-database" ;;
            *system-design*) icon_class="fas fa-sitemap" ;;
            *youtube*) icon_class="fab fa-youtube" ;;
            *) icon_class="fas fa-folder" ;;
        esac
    fi

    category_id=$(echo "$category" | sed 's/[^a-zA-Z0-9]/-/g')
    
    echo "                <div class=\"category-card\" id=\"category-$category_id\">"
    echo "                    <div class=\"category-header\">"
    echo "                        <span class=\"category-icon\"><i class=\"$icon_class\"></i></span>"
    echo "                        <div>"
    echo "                            <h3>$category_title</h3>"
    echo "                            <p>Explore articles and patterns in this area.</p>"
    echo "                        </div>"
    echo "                    </div>"
    echo "                    <ul class=\"file-list\">"
    
    # Parse files using ;;; as delimiter
    while IFS='|' read -r path title date; do
        [ -z "$path" ] && continue
        # Convert .md to .html for Jekyll output
        html_path="${path%.md}.html"
        echo "                        <li>"
        echo "                            <a href=\"$html_path\">"
        echo "                                <span class=\"file-icon\"><i class=\"fas fa-file-alt\"></i></span>"
        echo "                                <span class=\"file-title\">$title</span>"
        echo "                            </a>"
        echo "                        </li>"
    done <<< "$(echo "$files" | sed 's/;;;/\n/g')"
    
    echo "                    </ul>"
    echo "                </div>"
}

# Generate recent files (sorted by date, limit to 5)
generate_recent_html() {
    echo "            <section id=\"latest\" class=\"recent-section reveal\">"
    echo "                <div class=\"section-head\">"
    echo "                    <h2><span class=\"section-icon\"><i class=\"fas fa-clock\"></i></span> Latest Articles</h2>"
    echo "                    <p>Fresh insights and recent updates across system design topics.</p>"
    echo "                </div>"
    echo "                <div class=\"recent-grid\">"
    
    # Sort files by date and take top 6
    local sorted_files=$(for f in "${all_files[@]}"; do echo "$f"; done | sort -t'|' -k3 -r | head -6)
    
    while IFS='|' read -r path title date dir excerpt read_time; do
        [ -z "$path" ] && continue
        html_path="${path%.md}.html"
        local category_title
        if [ "$dir" = "." ]; then
            category_title="Getting Started"
        else
            category_title=$(to_title_case "$dir")
        fi
        if [ -z "$excerpt" ]; then
            excerpt="Read the full article for details and examples."
        fi
        
        echo "                    <a href=\"$html_path\" class=\"recent-card\">"
        echo "                        <div class=\"recent-meta\">"
        echo "                            <span class=\"recent-category\">$category_title</span>"
        echo "                            <span class=\"recent-date\">$date • $read_time min read</span>"
        echo "                        </div>"
        echo "                        <h4>$title</h4>"
        echo "                        <p>$excerpt</p>"
        echo "                    </a>"
    done <<< "$sorted_files"
    
    echo "                </div>"
    echo "            </section>"
}

# Generate recommended content
generate_recommended_html() {
    echo "            <section id=\"recommended\" class=\"recommended-section reveal\">"
    echo "                <div class=\"section-head\">"
    echo "                    <h2><span class=\"section-icon\"><i class=\"fas fa-star\"></i></span> Recommended Content</h2>"
    echo "                    <p>Curated essential reads for system design mastery.</p>"
    echo "                </div>"
    echo "                <div class=\"recommended-grid\">"
    
    # Prioritize certain topics as recommended
    local recommended_patterns=("microservices" "caching" "horizontal-scaling" "load-balancing")
    
    for pattern in "${recommended_patterns[@]}"; do
        for file_info in "${all_files[@]}"; do
            IFS='|' read -r path title date dir excerpt read_time <<< "$file_info"
            if [[ "$path" == *"$pattern"* ]]; then
                html_path="${path%.md}.html"
                local category_title
                if [ "$dir" = "." ]; then
                    category_title="Getting Started"
                else
                    category_title=$(to_title_case "$dir")
                fi
                if [ -z "$excerpt" ]; then
                    excerpt="Essential patterns and tradeoffs for building scalable systems."
                fi
                
                echo "                    <a href=\"$html_path\" class=\"recommended-card\">"
                echo "                        <div class=\"recommended-badge\"><i class=\"fas fa-gem\"></i> Essential</div>"
                echo "                        <div class=\"recommended-content\">"
                echo "                            <h4>$title</h4>"
                echo "                            <p>$excerpt</p>"
                echo "                        </div>"
                echo "                        <div class=\"recommended-footer\">"
                echo "                            <span class=\"recommended-category\">$category_title • $read_time min read</span>"
                echo "                        </div>"
                echo "                    </a>"
                break
            fi
        done
    done
    
    echo "                </div>"
    echo "            </section>"
}

# Generate featured article section with 3-4 featured items
generate_featured_html() {
    # Get top 4 articles by date
    local featured_files
    featured_files=$(for f in "${all_files[@]}"; do echo "$f"; done | sort -t'|' -k3 -r | head -4)
    
    # First article gets the hero treatment
    local count=0
    local first_article=""
    
    while IFS='|' read -r path title date dir excerpt read_time; do
        [ -z "$path" ] && continue
        if [ $count -eq 0 ]; then
            first_article="$path|$title|$date|$dir|$excerpt|$read_time"
        fi
        count=$((count + 1))
    done <<< "$featured_files"
    
    if [ -z "$first_article" ]; then
        return
    fi
    
    IFS='|' read -r path title date dir excerpt read_time <<< "$first_article"
    
    local html_path="${path%.md}.html"
    local category_title
    
    if [ "$dir" = "." ]; then
        category_title="Getting Started"
    else
        category_title=$(to_title_case "$dir")
    fi
    
    if [ -z "$excerpt" ]; then
        excerpt="Read the full article for frameworks, diagrams, and tradeoffs."
    fi
    
    # Main featured article
    echo "            <section class=\"featured-section reveal\">"
    echo "                <div class=\"featured-card\">"
    echo "                    <div class=\"featured-badge\"><i class=\"fas fa-star\"></i> Featured</div>"
    echo "                    <div class=\"featured-content\">"
    echo "                        <span class=\"featured-category\">$category_title</span>"
    echo "                        <h2>$title</h2>"
    echo "                        <p>$excerpt</p>"
    echo "                        <div class=\"featured-meta\"><i class=\"fas fa-calendar-alt\"></i> $date <i class=\"fas fa-clock\"></i> $read_time min read</div>"
    echo "                        <a class=\"featured-cta\" href=\"$html_path\"><i class=\"fas fa-book-open\"></i> Read the story</a>"
    echo "                    </div>"
    echo "                </div>"
    echo "            </section>"
    
    # Featured grid with remaining 3 articles
    echo "            <section class=\"featured-picks-section reveal\">"
    echo "                <div class=\"section-head\">"
    echo "                    <h2><span class=\"section-icon\"><i class=\"fas fa-fire\"></i></span> Editor's Picks</h2>"
    echo "                    <p>Hand-picked articles to accelerate your system design journey.</p>"
    echo "                </div>"
    echo "                <div class=\"featured-grid\">"
    
    count=0
    while IFS='|' read -r path title date dir excerpt read_time; do
        [ -z "$path" ] && continue
        count=$((count + 1))
        [ $count -eq 1 ] && continue  # Skip first (already featured)
        
        html_path="${path%.md}.html"
        if [ "$dir" = "." ]; then
            category_title="Getting Started"
        else
            category_title=$(to_title_case "$dir")
        fi
        if [ -z "$excerpt" ]; then
            excerpt="Explore patterns and best practices."
        fi
        
        echo "                    <a href=\"$html_path\" class=\"featured-item\">"
        echo "                        <span class=\"item-number\">$count</span>"
        echo "                        <h4>$title</h4>"
        echo "                        <p>$excerpt</p>"
        echo "                        <div class=\"item-meta\">"
        echo "                            <span>$category_title</span>"
        echo "                            <span><i class=\"fas fa-clock\"></i> $read_time min</span>"
        echo "                        </div>"
        echo "                    </a>"
    done <<< "$featured_files"
    
    echo "                </div>"
    echo "            </section>"
}

# Generate topics chips
generate_topics_html() {
    echo "            <section id=\"topics\" class=\"topics-section reveal\">"
    echo "                <div class=\"section-head\">"
    echo "                    <h2><span class=\"section-icon\"><i class=\"fas fa-tags\"></i></span> Topics</h2>"
    echo "                    <p>Browse by category to jump into a focused area.</p>"
    echo "                </div>"
    echo "                <div class=\"topics-grid\">"

    for cat in "${!categories[@]}"; do
        local label
        local category_id
        if [ "$cat" = "root" ]; then
            label="Getting Started"
        else
            label=$(to_title_case "$cat")
        fi
        category_id=$(echo "$cat" | sed 's/[^a-zA-Z0-9]/-/g')
        echo "                    <a class=\"topic-chip\" href=\"#category-$category_id\">$label</a>"
    done

    echo "                </div>"
    echo "            </section>"
}

# Count total files and categories
total_files=${#all_files[@]}
total_categories=${#categories[@]}

# Generate the index.html file
cat > index.html << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="System Design Deep Dive - Comprehensive guide to architecture patterns, design patterns, and scalability best practices">
    <meta name="keywords" content="system design, architecture patterns, microservices, scalability, design patterns">
    <title>System Design Deep Dive</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&family=Source+Serif+4:opsz,wght@8..60,400;8..60,600&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css" integrity="sha512-DTOQO9RWCH3ppGqcWaEA1BIZOC6xxalwEsw9c2QQeAIftl+Vegovlnee1c9QX4TctnWMn13TZye+giMm8e2LwA==" crossorigin="anonymous" referrerpolicy="no-referrer" />
    <link rel="stylesheet" href="assets/css/index.css">
    <link rel="stylesheet" href="assets/css/font-awesome-enhancements.css">
    <script defer src="assets/js/index.js"></script>
</head>
<body>
    <header class="site-header">
        <div class="container wide">
            <a href="./" class="brand"><i class="fas fa-book-open"></i> System Design Deep Dive</a>
            <nav class="nav-links" id="site-nav">
                <a href="#latest"><i class="fas fa-clock"></i> Latest</a>
                <a href="#recommended"><i class="fas fa-star"></i> Recommended</a>
                <a href="#topics"><i class="fas fa-tags"></i> Topics</a>
                <a href="#all-content"><i class="fas fa-th-list"></i> All Articles</a>
                <a href="https://github.com/Anilinfo2015/systemdesign-deepdive" target="_blank" rel="noreferrer"><i class="fab fa-github"></i> GitHub</a>
            </nav>
            <button class="nav-toggle" aria-label="Toggle navigation" aria-expanded="false" aria-controls="site-nav"><i class="fas fa-bars"></i></button>
        </div>
    </header>

    <section class="hero">
        <div class="container">
            <div class="hero-content">
                <span class="hero-eyebrow">Architecture • Patterns • Scalability</span>
                <h1>Design systems like a seasoned architect.</h1>
                <p>Deep dives, practical patterns, and battle-tested tradeoffs to help you build resilient, scalable platforms.</p>
                <div class="hero-actions">
                    <a class="btn primary" href="#all-content"><i class="fas fa-book-reader"></i> Browse library</a>
                    <a class="btn ghost" href="https://github.com/Anilinfo2015/systemdesign-deepdive" target="_blank" rel="noreferrer"><i class="fas fa-star"></i> Star on GitHub</a>
                </div>
                <div class="hero-stats">
                    <div class="stat">
                    <i class="fas fa-newspaper stat-icon"></i>
HTMLHEAD

echo "                    <span class=\"stat-number\">$total_files</span>" >> index.html
echo "                    <span class=\"stat-label\">Articles</span>" >> index.html
echo "                </div>" >> index.html
echo "                <div class=\"stat\">" >> index.html
echo "                    <i class=\"fas fa-layer-group stat-icon\"></i>" >> index.html
echo "                    <span class=\"stat-number\">$total_categories</span>" >> index.html
echo "                    <span class=\"stat-label\">Categories</span>" >> index.html
echo "                </div>" >> index.html
echo "                <div class=\"stat\">" >> index.html
echo "                    <i class=\"fas fa-infinity stat-icon\"></i>" >> index.html
echo "                    <span class=\"stat-number\">∞</span>" >> index.html
echo "                    <span class=\"stat-label\">Knowledge</span>" >> index.html
echo "                </div>" >> index.html

cat >> index.html << 'HTMLMID'
            </div>
        </div>
    </header>

    <main class="container" id="latest">
HTMLMID

# Featured section
generate_featured_html >> index.html

# Generate recent section
generate_recent_html >> index.html

# Generate recommended section
generate_recommended_html >> index.html

# Topics chips
generate_topics_html >> index.html

# Generate all content section
echo "            <section id=\"all-content\" class=\"all-content-section reveal\">" >> index.html
echo "                <h2><span class=\"section-icon\"><i class=\"fas fa-folder-open\"></i></span> All Content</h2>" >> index.html
echo "                <div class=\"categories-grid\">" >> index.html

# Output categories in a specific order
ordered_categories=("root" "architecture-patterns" "design-patterns" "scalability" "system-design")

for cat in "${ordered_categories[@]}"; do
    if [ -n "${categories[$cat]}" ]; then
        generate_category_html "$cat" "${categories[$cat]}" >> index.html
    fi
done

# Output any remaining categories not in the ordered list
for cat in "${!categories[@]}"; do
    if [[ ! " ${ordered_categories[*]} " =~ " ${cat} " ]]; then
        generate_category_html "$cat" "${categories[$cat]}" >> index.html
    fi
done

cat >> index.html << 'HTMLFOOT'
                </div>
            </section>

            <section class="cta-section reveal">
                <div class="cta-card">
                    <div>
                        <h2>Stay sharp on system design.</h2>
                        <p>Bookmark the library, follow updates, and keep a living reference for design interviews and real-world architecture.</p>
                    </div>
                    <div class="cta-actions">
                        <a class="btn primary" href="https://github.com/Anilinfo2015/systemdesign-deepdive" target="_blank" rel="noreferrer"><i class="fab fa-github"></i> Follow on GitHub</a>
                        <a class="btn ghost" href="https://github.com/Anilinfo2015/systemdesign-deepdive/issues" target="_blank" rel="noreferrer"><i class="fas fa-lightbulb"></i> Request a topic</a>
                    </div>
                </div>
            </section>
    </main>

    <!-- Back to Top Button -->
    <button class="back-to-top" aria-label="Back to top">
        <i class="fas fa-arrow-up"></i>
    </button>

    <footer class="footer">
        <div class="container">
            <div class="footer-content">
                <h3><i class="fas fa-book-open"></i> System Design Deep Dive</h3>
                <p>Your comprehensive resource for understanding system design concepts, architecture patterns, and best practices.</p>
                <div class="footer-links">
                    <a href="https://github.com/Anilinfo2015/systemdesign-deepdive"><i class="fab fa-github"></i> Repository</a>
                    <a href="https://github.com/Anilinfo2015/systemdesign-deepdive/issues"><i class="fas fa-bug"></i> Report Issue</a>
                    <a href="https://github.com/Anilinfo2015/systemdesign-deepdive/pulls"><i class="fas fa-code-branch"></i> Contribute</a>
                </div>
                <p class="copyright">© 2026 System Design Deep Dive. Built with ❤️ for developers.</p>
            </div>
        </div>
    </footer>
</body>
</html>
HTMLFOOT

echo "✅ index.html generated successfully!"
echo "📊 Found $total_files articles in $total_categories categories"
