from cassis import *
import lxml.etree as etree
import sys

def getval(node, attr):
	if attr in node.keys():
		return node.attrib[attr]
	return ""
	
def readback(filename):
	if "types" in cargs.keys():
		typefile = cargs["types"]
	else:
		typefile = "/Users/mjanssen/Git/dkpro-cassis/tests/test_files/typesystems/inception_typesystem.xml"
	if "verbose" in cargs.keys():
		print("Using TypeSystem from file: " + typefile)
	with open(typefile, 'rb') as f:
		typesystem = load_typesystem(f)
	
	Token = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.segmentation.type.Token')
	Sentence = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.segmentation.type.Sentence')
	Document = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.metadata.type.DocumentMetaData')
	Pos = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.lexmorph.type.pos.POS')
	Lemma = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.segmentation.type.Lemma')
	Morf = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.lexmorph.type.morph.MorphologicalFeatures')
	Deps = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.syntax.type.dependency.Dependency')

	if "infile" in cargs.keys():
		infile = cargs["infile"]
	else:
		infile = filename.replace('.xml', '.xmi')
	xmlf = etree.parse(filename)
	toks = {}
	tokfrom = {}
	tokto = {}
	docend = -1
	for tok in xmlf.findall("//text//tok"):
		tokid = tok.attrib['id']
		toks[tokid] = tok

	with open(infile, 'rb') as f:
	   cas = load_cas_from_xmi(f, typesystem=typesystem)

	# Read back the token based data
	for token in cas.select('de.tudarmstadt.ukp.dkpro.core.api.segmentation.type.Token'):
		tokid = token.id
		if token.end > docend:
			docend = token.end
		if not tokid:
			print('Token without an ID')
			print(token)
			continue
		tokfrom[token.begin] = tokid 
		tokto[token.end] = tokid 
		tok = toks[tokid]
		
		if token.pos:
			upos = token.pos.coarseValue
			if upos:
				tok.attrib['upos'] = upos
			xpos = token.pos.PosValue
			if xpos:
				tok.attrib['xpos'] = xpos

		if token.lemma:
			lemma = token.lemma.value
			tok.attrib['lemma'] = lemma

		if token.morph:
			morph = token.morph.value
			tok.attrib['feats'] = morph

		if "debug" in cargs.keys():
			print("Token " + tokid + " -> " + etree.tostring(tok, encoding='unicode', method='xml'))

	# Read back the dependency relations
	for dep in cas.select('de.tudarmstadt.ukp.dkpro.core.api.syntax.type.dependency.Dependency'):
		id1 = dep.Governor.id
		id2 = dep.Dependent.id
		deprel = dep.DependencyType
		toks[id1].attrib['deprel'] = deprel
		toks[id1].attrib['head'] = id2
		if "debug" in cargs.keys():
			print("Dependency " + id1 + " /" + deprel + "/ " + id2 + " -> " + etree.tostring(toks[id1], encoding='unicode', method='xml'))

	# Read back the Chunks
	for chunk in cas.select('de.tudarmstadt.ukp.dkpro.core.api.syntax.type.chunk.Chunk'):
		# Extend to full tokens
		p1 = chunk.begin
		while p1 > 0 and not p1 in tokfrom.keys():
			p1 = p1 - 1 
		p2 = chunk.end
		while p2 < docend and not p2 in tokto.keys():
			p2 = p2 + 1 
		tok1 = tokfrom[p1]
		tok2 = tokto[p2]
		if "debug" in cargs.keys():
			print("Chunk " + tok1 + " - " + tok2 + ": " + chunk.chunkValue)

	# Read back the Named Entities
	for ner in cas.select('de.tudarmstadt.ukp.dkpro.core.api.ner.type.NamedEntity'):
		# Extend to full tokens
		p1 = ner.begin
		while p1 > 0 and not p1 in tokfrom.keys():
			p1 = p1 - 1 
		p2 = ner.end
		while p2 < docend and not p2 in tokto.keys():
			p2 = p2 + 1 
		tok1 = tokfrom[p1]
		tok2 = tokto[p2]
		if "debug" in cargs.keys():
			print("Named Entities " + tok1 + " - " + tok2 + ": " + ner.value)

	if "test" in cargs.keys():
		print(etree.tostring(xmlf, pretty_print=True, encoding='unicode', method='xml'))
		exit()
	xmlf.write(filename)
			
fname = ""
cargs = {}
for arg in sys.argv[1:]:
	if arg[0:1] == "-":
		tmp = arg[2:].split("=")
		if len(tmp) == 1:
			tmp.append(1);
		cargs[tmp[0]] = tmp[1]
	else:
		fname = arg
if "file" in cargs.keys():
	fname = cargs['file']
if fname == "":
	cargs["help"] = 1

if "debug" in cargs.keys():
	cargs["verbose"] = 1
if "verbose" in cargs.keys() and fname:
	print("Processing XML file: " + fname)

if "help" in cargs.keys():
	print('''Usage: python cas2teitok.py [options] FILENAME

Options:
--help         : show this help
--verbose      : verbose mode
--debug        : debug mode
--test         : print output to STDOUT
--file=FILE    : XML filename for readback
--infile=FILE  : XMI input filename
--types=FILE   : TypeSystem filename
''')
	exit()

readback(fname)