import sys
import os
import base64
from docx import Document
from lxml import etree
from datetime import date
import zipfile
from pathlib import Path
from io import BytesIO

def extract_images_and_map_relationships(docx_path):
    """
    Extract images from a DocX file and map relationship IDs to image filenames.
    """

    # Open the DocX file as a ZIP archive
    with zipfile.ZipFile(docx_path) as docx_zip:
        # Extract all files in the 'word/media' directory
        image_files = [f for f in docx_zip.namelist() if f.startswith("word/media/")]

        # Save images and map their relationship IDs
        for idx, image_file in enumerate(image_files):
            # Get the image filename and extension
            image_filename = os.path.basename(image_file)

            # Save the image to the output directory
            output_path = os.path.join(image_dir, image_filename)

            if not os.path.exists(image_dir):
                os.makedirs(image_dir)

            with docx_zip.open(image_file) as image_data:
                with open(output_path, "wb") as img_file:
                    img_file.write(image_data.read())

            # Map the relationship ID to the saved image filename
            relationship_id = os.path.splitext(image_filename)[0]
            image_map[relationship_id] = image_filename

        # Parse the document relationships to map relationship IDs to image paths
        rels_path = "word/_rels/document.xml.rels"
        if rels_path in docx_zip.namelist():
            with docx_zip.open(rels_path) as rels_file:
                rels_xml = rels_file.read()
                rels_root = etree.fromstring(rels_xml)

                for rel in rels_root.findall(".//{http://schemas.openxmlformats.org/package/2006/relationships}Relationship"):
                    if "image" in rel.get("Type"):
                        relationship_id = rel.get("Id")
                        target = rel.get("Target")
                        if target.startswith("media/"):
                            image_filename = os.path.basename(target)
                            image_map[relationship_id] = image_filename

    return image_map

def get_color(run):
    """Extract font color from the run."""
    if run.font.color and run.font.color.rgb:
        return f"color: #{run.font.color.rgb};"
    return ""

def get_font_size(run):
    """Extract font size in points."""
    return f"font-size: {run.font.size.pt}pt;" if run.font.size else ""

def get_text_styles(run):
    """Extract text styles like bold, italic, underline, superscript."""
    styles = []
    if run.bold:
        styles.append("font-weight: bold;")
    if run.italic:
        styles.append("font-style: italic;")
    if run.underline:
        styles.append("text-decoration: underline;")
    if run.font.superscript:
        styles.append("vertical-align: super; font-size: smaller;")
    if run.font.subscript:
        styles.append("vertical-align: sub; font-size: smaller;")
    return " ".join(styles)

def get_background_color(para):
    """Extract background color from a paragraph's XML structure."""
    try:
        shading = para._element.xpath(".//w:shd", namespaces={'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'})
        if shading and "w:fill" in shading[0].attrib:
            color = shading[0].attrib["w:fill"]
            if color and color != "auto":  # Ignore default "auto" colors
                return f"background-color: #{color};"
    except Exception:
        pass
    return ""

def process_run(run):
    """Convert a run (styled text) to TEI <hi> with a single style attribute."""
    text_elem = etree.Element("hi")

    # Collect all styles
    styles = get_color(run) + get_font_size(run) + get_text_styles(run)
    if styles:
        text_elem.set("style", styles.strip())

    xml_str = run._element.xml
    if "w:footnoteReference" in xml_str:
        # Extract footnote ID
        run_xml = etree.fromstring(xml_str)
        for footnote_ref in run_xml.findall(".//w:footnoteReference", namespaces):
            footnote_id = footnote_ref.get("{http://schemas.openxmlformats.org/wordprocessingml/2006/main}id")
            if footnote_id in footnote_map:
                # Replace with a clickable link
                text_elem = etree.Element("note")
                text_elem.set("id", "fn-" + str(footnote_id))
                text_elem.text = footnote_map.get(footnote_id)
    else:
        text_elem.text = run.text

    return text_elem

def extract_hyperlinks(doc):
    """Extract all hyperlinks from the document."""
    hyperlinks = {}
    for rel in doc.part.rels:
        if "hyperlink" in doc.part.rels[rel].reltype:
            hyperlinks[doc.part.rels[rel].rId] = doc.part.rels[rel].target_ref
    return hyperlinks

def append_mixed_content(src, dst):
    """ Append all children and text content from `src` to `dst` in the correct order. """

    # Find the last node in the destination (last child OR text)
    last_child = dst[-1] if len(dst) > 0 else None

    # If there's existing text and no elements, append to the text
    if last_child is None:
        dst.text = (dst.text or "") + (src.text or "")
    else:
        # If there's already an element, append new text to its tail
        last_child.tail = (last_child.tail or "") + (src.text or "")

    # Append each child while preserving order
    for child in src:
        copied_child = copy.deepcopy(child)  # Copy child element
        dst.append(copied_child)  # Append to destination

        if child.tail:
            copied_child.tail = child.tail  # Preserve tail text after each element
            
def process_paragraph(para, hyperlinks):
    """Convert a paragraph to TEI."""

    para_elem = etree.Element("p")
    para_elem.tail = "\n"

    # Extract paragraph background color
    background_color = get_background_color(para)
    if background_color:
        para_elem.set("style", background_color.strip())
    
    lasthi = para_elem
    for run in para.runs:
        # Check if run is part of a hyperlink
        r_id = run._element.getparent().get("r:id")
        if r_id and r_id in hyperlinks:
            ref_elem = etree.Element("ref", target=hyperlinks[r_id])
            ref_elem.text = run.text
            para_elem.append(ref_elem)
        else:
            hi = process_run(run)
            if len(hi) > 0 or ( hi.text is not None and hi.text):
                # Skip empty elements
                if not hi.attrib: 
                    # Add to the paragraph directly if there is no styling
                    append_mixed_content(hi, para_elem)
                    lasthi = para_elem
                elif hi.get("style") == lasthi.get("style"):
                    # Add to the last hi if styling has not changed
                    append_mixed_content(hi, lasthi)
                else:
                    # Add the new hi element
                    para_elem.append(hi)
                    lasthi = hi                

        # Handle images
        for drawing in run._element.findall(".//w:drawing", namespaces=namespaces):
            blip = drawing.find(".//a:blip", namespaces=namespaces)
            if blip is not None:
                relationship_id = blip.get("{http://schemas.openxmlformats.org/officeDocument/2006/relationships}embed")
                if relationship_id:
                    # Find the corresponding image filename
                    image_filename = image_map.get(relationship_id)
                    if image_filename:
                        # Add a <figure> and <graphic> element to the TEI
                        figure = etree.SubElement(para_elem, "figure")
                        graphic = etree.SubElement(figure, "graphic", url=os.path.join(image_reldir, image_filename))
    
    # Skip the paragraph if it is empty
    if len(para_elem) == 0 and not para_elem.text:
        return None

    return para_elem

def process_table(table):
    """Convert a DOCX table to TEI."""
    table_elem = etree.Element("table")
    
    for row in table.rows:
        row_elem = etree.Element("row")
        for cell in row.cells:
            cell_elem = etree.Element("cell")
            for para in cell.paragraphs:
                processed_para = process_paragraph(para, {})
                if processed_para is not None:  # Explicit check
                    cell_elem.append(processed_para)
            row_elem.append(cell_elem)
        table_elem.append(row_elem)

    return table_elem

def extract_footnotes(doc):
    """Extract footnotes manually from docx XML."""
    footnotes_elem = etree.Element("notes")
 
    footnotes_part = None
    for rel in doc.part.rels.values():
        if "footnotes" in rel.target_ref:
            footnotes_part = rel.target_part
            break
            
    if not footnotes_part:
        return

    fncnt = 1
    footnotes_xml = etree.parse(BytesIO(footnotes_part.blob))
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    for footnote in footnotes_xml.findall("w:footnote", ns):
        footnote_id = footnote.get("{http://schemas.openxmlformats.org/wordprocessingml/2006/main}id")
        fntext = "".join(node.text or "" for node in footnote.findall(".//w:t", ns))
        note_elem = etree.Element("note")
        note_elem.text = fntext
        footnote_id = footnote.get("{http://schemas.openxmlformats.org/wordprocessingml/2006/main}id")
        note_elem.set("id", "fn-" + footnote_id)
        fncnt = fncnt + 1
        footnotes_elem.append(note_elem)
        footnote_map[footnote_id] = fntext

    # Skip the paragraph if it is empty
    if len(footnotes_elem) == 0 and not footnotes_elem.text:
        return None

    return footnotes_elem

def convert_docx_to_tei(docx_file, output_tei_file):
    doc = Document(docx_file)

    image_map = extract_images_and_map_relationships(docx_file)
    footnotes = extract_footnotes(doc)
    
    # Extract hyperlinks
    hyperlinks = extract_hyperlinks(doc)

    XML_NS = "http://www.w3.org/XML/1998/namespace"

    # Create TEI structure
    tei = etree.Element("TEI")
    tei_header = etree.SubElement(tei, "teiHeader")
    text = etree.SubElement(tei, "text")
    text.set(f"{{{XML_NS}}}space", "preserve")
    text.set("id", os.path.splitext(os.path.basename(docx_file))[0])
    body = etree.SubElement(text, "body")


    filedesc = etree.SubElement(tei_header, "fileDesc")
    notesstmt = etree.SubElement(filedesc, "notesStmt")
    note = etree.SubElement(notesstmt, "note")
    note.set("n", "orgfile")
    note.text = docx_file
    revisiondesc = etree.SubElement(tei_header, "revisionDesc")
    change = etree.SubElement(revisiondesc, "change")
    change.set("who", "docx2tei")
    today = str(date.today())
    change.set("when", today)
    change.text = "Converted from DOCX file"

    # Map the docx elements onto a map
    para_map = {}
    for para in doc.paragraphs:
        para_map[para._element] = para  # Map lxml element to python-docx paragraph
    table_map = {}
    for table in doc.tables:
        table_map[table._element] = table  # Map lxml element to python-docx paragraph

    # Iterate through the document body in order
    for element in doc._element.findall(".//w:body/*", namespaces=namespaces):
        if element.tag.endswith("p"):  # Paragraph
            processed_element = process_paragraph(para_map.get(element), hyperlinks)
        elif element.tag.endswith("tbl"):  # Table
            processed_element = process_table(table_map.get(element))
        elif element.tag.endswith("sectPr"):  # Table
            # Section Properties - skip
            pass
        else:
            print("Unknown: ", element.tag)
            
        if processed_element is not None:  # Explicit check
            body.append(processed_element)

    # Place footnotes (endnotes) - make it optional!
#     if footnotes is not None:
#         text.append(footnotes)

    # Save TEI XML
    tree = etree.ElementTree(tei)
    tree.write(output_tei_file, pretty_print=True, xml_declaration=True, encoding="utf-8")

    print(f"Conversion complete! Saved as {output_tei_file}")

# Command-line usage
if len(sys.argv) < 1:
    print("Usage: python convert_docx_to_tei.py <input.docx> ")
    sys.exit(1)

docx_filename = sys.argv[1]
fileid = os.path.splitext(os.path.basename(docx_filename))[0]

# Determine default TEITOK style filenames or default to generic names
if len(sys.argv) > 2: tei_filename = sys.argv[2] 
else:
    index = docx_filename.find("Originals")
    if index != -1:
        tei_filename = docx_filename[:index] + "xmlfiles/" + fileid + ".xml"
        fileid = os.path.splitext(os.path.basename(docx_filename))[0]
    else:
        tei_filename = os.path.splitext(docx_filename)[0] + ".xml"

if len(sys.argv) > 3: image_dir = sys.argv[3] 
else:
    index = tei_filename.find("xmlfiles")
    if index != -1:
        image_dir = tei_filename[:index] + "Graphics/" + fileid
    else:
        image_dir = os.path.splitext(tei_filename)[0] + "_files"

# Determine what to put as the link for images
path = Path(image_dir)
if path.parts[-2] == "Graphics":
    image_reldir = path.parts[-1]
else:
    image_reldir = image_dir
    
# Define global variables to hold the image and footnote references
image_map = {}
footnote_map = {}

namespaces = {
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "pic": "http://schemas.openxmlformats.org/drawingml/2006/picture",
}

convert_docx_to_tei(docx_filename, tei_filename)
