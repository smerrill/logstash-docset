require 'rubygems'
require 'nokogiri'
require 'sqlite3'
require 'find'

# Grab files.
`rm -frv logstash.docset/Contents/Resources/Documents/*`
`wget -P logstash.docset/Contents/Resources/Documents --mirror logstash.net/docs/1.4.2`
`find logstash.docset/Contents/Resources/Documents -name '*.html' -exec rm {} \\;`
`find logstash.docset/Contents/Resources/Documents -type f ! -name '*.*' -exec mv {} {}.html \\;`

# Create the search index database.
db = SQLite3::Database.new 'logstash.docset/Contents/Resources/docSet.dsidx'
db.execute 'DROP TABLE IF EXISTS searchIndex;'
db.execute 'CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);'
db.execute 'CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);'

# @TODO: Make this a changeable option.
ls_version = '1.4.2'
docs_path = "logstash.docset/Contents/Resources/Documents/logstash.net/docs/#{ls_version}"

# Drop 4 items from the path to get the relative path.
def relative_path(path)
  path.split('/').drop(5).join('/')
end

# Convert image and CSS paths to be relative instead of absolute.
def fix_paths(doc, count, path)
  doc.xpath('//img').each do |x|
    if x['src'].start_with?('//') or x['src'].start_with?('media')
      next
    end
    if x['src'].start_with?('/')
      x['src'] = Array.new(count, "../").join + x['src']
    end
  end
  doc.xpath('//link[@rel="stylesheet"]').each do |y|
    if y['href'].start_with?('/')
     y['href'] = Array.new(count, "../").join + y['href']
    end
  end
  doc.xpath('//a').each do |z|
    # Ignore links that only go to anchors.
    if !z['href']
      next
      end
    # Ignore links to anchors and real pages.
    if z['href'].start_with?('#') or z['href'].start_with?('http')
      next
    end

    # Actually rewrite the paths now.
    if z['href'] == '/'
      z['href'] = 'http://logstash.net/'
    end
    # Don't rewrite paths that already contain '.html'
    if z['href'] =~ /\.html/
      next
    end

    url, hash = z['href'].split('#')
    url += '.html'
    url = "#{url}\##{hash}" if hash
    z['href'] = url
  end
end

def index_page(db, name, path)
  type = 'Guide'
  if path =~ /filters/
    type = 'Filter'
  elsif path =~ /(inputs|codecs|outputs)/
    type = 'Plugin'
  end

  db.execute('INSERT INTO searchIndex (name, type, path) VALUES (?, ?, ?)',
    [name, type, "logstash.net/#{path}"])
end

# Find all files and operate on them.
Find.find(docs_path) do |path|
  if FileTest.file?(path)
    if File.extname(path) != ".html"
      next
    end

    doc = Nokogiri::HTML(open(path))

    begin
      name = doc.css('h2').first.content
    rescue
      name = File.split(path).last.gsub(/\.html/, '').gsub(/-/, ' ').gsub(/\w+/, &:capitalize)
    end

    relative_path = relative_path(path)
    directory_count = relative_path.scan(/\//).count

    # Convert image and CSS paths into relative paths.
    fix_paths(doc, directory_count, relative_path)
    File.open(path,'w') {|f| doc.write_html_to f}

    # Fill the SQLite database with information!
    index_page(db, name, relative_path)
  end
  if File.basename(path)[0] == ?.
    Find.prune
  end
end
