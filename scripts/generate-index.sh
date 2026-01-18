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

# Collect all markdown files organized by directory
declare -A categories
declare -a all_files
declare -a file_dates

# Find all markdown files
while IFS= read -r -d '' file; do
    # Skip hidden files and directories
    [[ "$file" =~ ^\./\. ]] && continue
    [[ "$file" =~ ^\./_ ]] && continue
    
    # Get relative path without ./
    rel_path="${file#./}"
    
    # Get directory
    dir=$(dirname "$rel_path")
    
    # Get file info
    title=$(get_md_title "$file")
    date=$(get_file_date "$file")
    
    # Store file info
    all_files+=("$rel_path|$title|$date|$dir")
    
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
    
    if [ "$category" = "root" ]; then
        category_title="Getting Started"
        icon="🚀"
    else
        category_title=$(to_title_case "$category")
        case "$category" in
            *design*) icon="🎨" ;;
            *architecture*) icon="🏗️" ;;
            *scalability*) icon="📈" ;;
            *security*) icon="🔒" ;;
            *database*) icon="💾" ;;
            *pattern*) icon="🧩" ;;
            *) icon="📂" ;;
        esac
    fi
    
    echo "                <div class=\"category-card\">"
    echo "                    <div class=\"category-header\">"
    echo "                        <span class=\"category-icon\">$icon</span>"
    echo "                        <h3>$category_title</h3>"
    echo "                    </div>"
    echo "                    <ul class=\"file-list\">"
    
    # Parse files using ;;; as delimiter
    while IFS='|' read -r path title date; do
        [ -z "$path" ] && continue
        # Convert .md to .html for Jekyll output
        html_path="${path%.md}.html"
        echo "                        <li>"
        echo "                            <a href=\"$html_path\">"
        echo "                                <span class=\"file-icon\">📄</span>"
        echo "                                <span class=\"file-title\">$title</span>"
        echo "                            </a>"
        echo "                        </li>"
    done <<< "$(echo "$files" | sed 's/;;;/\n/g')"
    
    echo "                    </ul>"
    echo "                </div>"
}

# Generate recent files (sorted by date, limit to 5)
generate_recent_html() {
    echo "            <section class=\"recent-section\">"
    echo "                <h2><span class=\"section-icon\">🕐</span> Recent Updates</h2>"
    echo "                <div class=\"recent-grid\">"
    
    # Sort files by date and take top 5
    local sorted_files=$(for f in "${all_files[@]}"; do echo "$f"; done | sort -t'|' -k3 -r | head -5)
    
    while IFS='|' read -r path title date dir; do
        [ -z "$path" ] && continue
        html_path="${path%.md}.html"
        local category_title
        if [ "$dir" = "." ]; then
            category_title="Getting Started"
        else
            category_title=$(to_title_case "$dir")
        fi
        
        echo "                    <a href=\"$html_path\" class=\"recent-card\">"
        echo "                        <div class=\"recent-meta\">"
        echo "                            <span class=\"recent-category\">$category_title</span>"
        echo "                            <span class=\"recent-date\">$date</span>"
        echo "                        </div>"
        echo "                        <h4>$title</h4>"
        echo "                    </a>"
    done <<< "$sorted_files"
    
    echo "                </div>"
    echo "            </section>"
}

# Generate recommended content
generate_recommended_html() {
    echo "            <section class=\"recommended-section\">"
    echo "                <h2><span class=\"section-icon\">⭐</span> Recommended Content</h2>"
    echo "                <div class=\"recommended-grid\">"
    
    # Prioritize certain topics as recommended
    local recommended_patterns=("microservices" "caching" "horizontal-scaling" "load-balancing")
    
    for pattern in "${recommended_patterns[@]}"; do
        for file_info in "${all_files[@]}"; do
            IFS='|' read -r path title date dir <<< "$file_info"
            if [[ "$path" == *"$pattern"* ]]; then
                html_path="${path%.md}.html"
                local category_title
                if [ "$dir" = "." ]; then
                    category_title="Getting Started"
                else
                    category_title=$(to_title_case "$dir")
                fi
                
                echo "                    <a href=\"$html_path\" class=\"recommended-card\">"
                echo "                        <div class=\"recommended-badge\">Recommended</div>"
                echo "                        <h4>$title</h4>"
                echo "                        <span class=\"recommended-category\">$category_title</span>"
                echo "                    </a>"
                break
            fi
        done
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
    <style>
        :root {
            --primary: #667eea;
            --primary-dark: #5a67d8;
            --secondary: #764ba2;
            --accent: #f093fb;
            --text-dark: #1a1a2e;
            --text-light: #4a5568;
            --bg-light: #f7fafc;
            --bg-white: #ffffff;
            --shadow: 0 4px 20px rgba(102, 126, 234, 0.15);
            --shadow-hover: 0 8px 30px rgba(102, 126, 234, 0.25);
            --radius: 16px;
            --radius-sm: 8px;
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.7;
            color: var(--text-dark);
            background: var(--bg-light);
            min-height: 100vh;
        }

        /* Hero Section */
        .hero {
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            color: white;
            padding: 80px 20px;
            text-align: center;
            position: relative;
            overflow: hidden;
        }

        .hero::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: url("data:image/svg+xml,%3Csvg width='60' height='60' viewBox='0 0 60 60' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fill-rule='evenodd'%3E%3Cg fill='%23ffffff' fill-opacity='0.05'%3E%3Cpath d='M36 34v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6 34v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6 4V0H4v4H0v2h4v4h2V6h4V4H6z'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E");
        }

        .hero-content {
            position: relative;
            z-index: 1;
            max-width: 800px;
            margin: 0 auto;
        }

        .hero h1 {
            font-size: 3.5rem;
            font-weight: 800;
            margin-bottom: 20px;
            text-shadow: 0 2px 10px rgba(0,0,0,0.2);
        }

        .hero-emoji {
            font-size: 4rem;
            display: block;
            margin-bottom: 20px;
        }

        .hero p {
            font-size: 1.3rem;
            opacity: 0.95;
            max-width: 600px;
            margin: 0 auto 30px;
        }

        .hero-stats {
            display: flex;
            justify-content: center;
            gap: 50px;
            margin-top: 40px;
        }

        .stat {
            text-align: center;
        }

        .stat-number {
            font-size: 2.5rem;
            font-weight: 700;
            display: block;
        }

        .stat-label {
            font-size: 0.9rem;
            opacity: 0.85;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        /* Navigation */
        .nav-bar {
            background: rgba(255,255,255,0.95);
            backdrop-filter: blur(10px);
            position: sticky;
            top: 0;
            z-index: 1000;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }

        .nav-container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 15px 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .nav-brand {
            font-weight: 700;
            font-size: 1.3rem;
            color: var(--primary);
            text-decoration: none;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .nav-links {
            display: flex;
            gap: 25px;
        }

        .nav-links a {
            color: var(--text-light);
            text-decoration: none;
            font-weight: 500;
            transition: color 0.3s;
        }

        .nav-links a:hover {
            color: var(--primary);
        }

        /* Main Container */
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 60px 20px;
        }

        /* Sections */
        section {
            margin-bottom: 60px;
        }

        section h2 {
            font-size: 2rem;
            color: var(--text-dark);
            margin-bottom: 30px;
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .section-icon {
            font-size: 1.5rem;
        }

        /* Recent Section */
        .recent-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
        }

        .recent-card {
            background: var(--bg-white);
            padding: 25px;
            border-radius: var(--radius);
            text-decoration: none;
            color: var(--text-dark);
            box-shadow: var(--shadow);
            transition: all 0.3s ease;
            border-left: 4px solid var(--primary);
        }

        .recent-card:hover {
            transform: translateY(-5px);
            box-shadow: var(--shadow-hover);
        }

        .recent-meta {
            display: flex;
            justify-content: space-between;
            margin-bottom: 12px;
            font-size: 0.85rem;
        }

        .recent-category {
            color: var(--primary);
            font-weight: 600;
        }

        .recent-date {
            color: var(--text-light);
        }

        .recent-card h4 {
            font-size: 1.15rem;
            color: var(--text-dark);
        }

        /* Recommended Section */
        .recommended-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 25px;
        }

        .recommended-card {
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            padding: 30px;
            border-radius: var(--radius);
            text-decoration: none;
            color: white;
            position: relative;
            overflow: hidden;
            transition: all 0.3s ease;
        }

        .recommended-card:hover {
            transform: translateY(-5px) scale(1.02);
            box-shadow: var(--shadow-hover);
        }

        .recommended-badge {
            position: absolute;
            top: 15px;
            right: 15px;
            background: rgba(255,255,255,0.2);
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 0.75rem;
            font-weight: 600;
        }

        .recommended-card h4 {
            font-size: 1.3rem;
            margin-bottom: 10px;
            margin-top: 10px;
        }

        .recommended-category {
            opacity: 0.85;
            font-size: 0.9rem;
        }

        /* Categories Grid */
        .categories-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 30px;
        }

        .category-card {
            background: var(--bg-white);
            border-radius: var(--radius);
            box-shadow: var(--shadow);
            overflow: hidden;
            transition: all 0.3s ease;
        }

        .category-card:hover {
            box-shadow: var(--shadow-hover);
        }

        .category-header {
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            padding: 25px;
            color: white;
            display: flex;
            align-items: center;
            gap: 15px;
        }

        .category-icon {
            font-size: 2rem;
        }

        .category-header h3 {
            font-size: 1.4rem;
            font-weight: 600;
        }

        .file-list {
            list-style: none;
            padding: 20px;
        }

        .file-list li {
            margin-bottom: 8px;
        }

        .file-list a {
            display: flex;
            align-items: center;
            padding: 15px 18px;
            background: var(--bg-light);
            border-radius: var(--radius-sm);
            text-decoration: none;
            color: var(--text-dark);
            transition: all 0.3s ease;
            gap: 12px;
        }

        .file-list a:hover {
            background: linear-gradient(135deg, rgba(102, 126, 234, 0.1) 0%, rgba(118, 75, 162, 0.1) 100%);
            transform: translateX(8px);
        }

        .file-icon {
            font-size: 1.2rem;
        }

        .file-title {
            font-weight: 500;
        }

        /* Footer */
        .footer {
            background: var(--text-dark);
            color: white;
            padding: 60px 20px;
            text-align: center;
        }

        .footer-content {
            max-width: 600px;
            margin: 0 auto;
        }

        .footer h3 {
            font-size: 1.5rem;
            margin-bottom: 15px;
        }

        .footer p {
            opacity: 0.8;
            margin-bottom: 25px;
        }

        .footer-links {
            display: flex;
            justify-content: center;
            gap: 30px;
        }

        .footer-links a {
            color: white;
            text-decoration: none;
            opacity: 0.8;
            transition: opacity 0.3s;
        }

        .footer-links a:hover {
            opacity: 1;
        }

        .copyright {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid rgba(255,255,255,0.1);
            opacity: 0.6;
            font-size: 0.9rem;
        }

        /* Responsive */
        @media (max-width: 768px) {
            .hero h1 {
                font-size: 2.2rem;
            }

            .hero-stats {
                flex-direction: column;
                gap: 25px;
            }

            .nav-links {
                display: none;
            }

            .categories-grid {
                grid-template-columns: 1fr;
            }

            section h2 {
                font-size: 1.5rem;
            }
        }
    </style>
</head>
<body>
    <nav class="nav-bar">
        <div class="nav-container">
            <a href="/" class="nav-brand">📚 System Design Deep Dive</a>
            <div class="nav-links">
                <a href="#recent">Recent</a>
                <a href="#recommended">Recommended</a>
                <a href="#all-content">All Content</a>
                <a href="https://github.com/Anilinfo2015/systemdesign-deepdive" target="_blank">GitHub</a>
            </div>
        </div>
    </nav>

    <header class="hero">
        <div class="hero-content">
            <span class="hero-emoji">📚</span>
            <h1>System Design Deep Dive</h1>
            <p>Comprehensive guide to architecture patterns, design patterns, and scalability best practices for building robust systems</p>
            <div class="hero-stats">
                <div class="stat">
HTMLHEAD

echo "                    <span class=\"stat-number\">$total_files</span>" >> index.html
echo "                    <span class=\"stat-label\">Articles</span>" >> index.html
echo "                </div>" >> index.html
echo "                <div class=\"stat\">" >> index.html
echo "                    <span class=\"stat-number\">$total_categories</span>" >> index.html
echo "                    <span class=\"stat-label\">Categories</span>" >> index.html
echo "                </div>" >> index.html
echo "                <div class=\"stat\">" >> index.html
echo "                    <span class=\"stat-number\">∞</span>" >> index.html
echo "                    <span class=\"stat-label\">Knowledge</span>" >> index.html
echo "                </div>" >> index.html

cat >> index.html << 'HTMLMID'
            </div>
        </div>
    </header>

    <main class="container">
HTMLMID

# Generate recent section
generate_recent_html >> index.html

# Generate recommended section
generate_recommended_html >> index.html

# Generate all content section
echo "            <section id=\"all-content\" class=\"all-content-section\">" >> index.html
echo "                <h2><span class=\"section-icon\">📂</span> All Content</h2>" >> index.html
echo "                <div class=\"categories-grid\">" >> index.html

# Output categories in a specific order
ordered_categories=("root" "architecture-patterns" "design-patterns" "scalability")

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
    </main>

    <footer class="footer">
        <div class="footer-content">
            <h3>System Design Deep Dive</h3>
            <p>Your comprehensive resource for understanding system design concepts, architecture patterns, and best practices.</p>
            <div class="footer-links">
                <a href="https://github.com/Anilinfo2015/systemdesign-deepdive">📦 Repository</a>
                <a href="https://github.com/Anilinfo2015/systemdesign-deepdive/issues">🐛 Report Issue</a>
                <a href="https://github.com/Anilinfo2015/systemdesign-deepdive/pulls">🔀 Contribute</a>
            </div>
            <p class="copyright">© 2024 System Design Deep Dive. Built with ❤️ for developers.</p>
        </div>
    </footer>
</body>
</html>
HTMLFOOT

echo "✅ index.html generated successfully!"
echo "📊 Found $total_files articles in $total_categories categories"
