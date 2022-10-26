from cassis import *
import lxml.etree as etree
import sys


def getval(node, attr):
	if attr in node.keys():
		return node.attrib[attr]
	return ""
	
	
with open('/Users/mjanssen/Git/dkpro-cassis/tests/test_files/typesystems/inception_typesystem.xml', 'rb') as f:
    typesystem = load_typesystem(f)

Token = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.segmentation.type.Token')
Sentence = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.segmentation.type.Sentence')
Document = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.metadata.type.DocumentMetaData')
Pos = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.lexmorph.type.pos.POS')
Lemma = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.segmentation.type.Lemma')
Morf = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.lexmorph.type.morph.MorphologicalFeatures')
Deps = typesystem.get_type('de.tudarmstadt.ukp.dkpro.core.api.syntax.type.dependency.Dependency')

def convert(filename):
	xmlf = etree.parse(filename)
	cas = Cas(typesystem=typesystem)

	if len(xmlf.findall("//text//tok")) == 0:
		print("Document not a TEITOK XML file or not tokenized")
		exit()
	if len(xmlf.findall("//text//s")) == 0:
		print("Document not segmented into sentences")
		exit()

	sofastr = ""
	space = ""

	# Add all sentences with all tokens
	sentcnt = 1
	begin = -0
	end = -1
	toks = {}
	deprels = []
	for sent in xmlf.findall("//text//s"):
		sentid = "s-" + str(sentcnt)
		sentcnt = sentcnt + 1
		sentbegin = end + 1
		if "id" in sent.keys():
			sentid = sent.attrib['id']
		if "debug" in cargs.keys():
			print("-- " + sentid)
		if "sameAs" in sent.keys():
			stoks = []
			for tokid in sent.attrib['sameAs'].split(" "):
				tok = xmlf.find("//*[@id=\""+tokid[1:]+"\"]")
				stoks.append(tok)
		else:
			stoks = sent.findall(".//tok")		
		for tok in stoks:
			word = tok.text
			tokid = tok.attrib['id']
			strlen = len(word)
			begin = end + 1
			end += strlen + 1
			toks[tokid] = Token(begin=begin, end=end, id=tokid)
			if "upos" in tok.keys() or "xpos"  in tok.keys():
				tpos = Pos(begin=begin, end=end, coarseValue=getval(tok, "upos"), PosValue=getval(tok, "xpos"))
				toks[tokid].pos = tpos
				cas.add(tpos)
			if "lemma" in tok.keys():
				tlemma = Lemma(begin=begin, end=end, value=tok.attrib["lemma"])
				cas.add(tlemma)
				toks[tokid].lemma = tlemma
			if "feats" in tok.keys():
				tmorf = Morf(begin=begin, end=end, value=tok.attrib["feats"])
				toks[tokid].morph = tmorf
				cas.add(tmorf)
			if "debug" in cargs.keys():
				print(tokid + ': ' + word + " -> " + str(strlen) + " = " + str(begin) + " - " + str(end))
			sofastr += space + word
			space = " "
			if "head" in tok.keys() and "deprel"  in tok.keys():
				deprels.append({'Governor': tokid, 'Dependent': tok.attrib['head'], 'DependencyType': tok.attrib['deprel']})
			cas.add(toks[tokid])
		if end > sentbegin:
			cas.add(Sentence(begin=sentbegin, end=end, id=sentid))

	for deprel in deprels:
		tok1 = toks[deprel['Governor']]
		tok2 = toks[deprel['Dependent']]
		cas.add(Deps(Governor=tok1, Dependent=tok2, DependencyType=deprel['DependencyType'], flavor="basic", begin=tok2['begin'], end=tok2['end']))

	# Add the full string to the sofa
	cas.sofa_string = sofastr

	xmi = cas.to_xmi()    
	# print(xmi)

	if "outfile" in cargs.keys():
		outfile = cargs["outfile"]
	else:
		outfile = filename.replace('.xml', '.xmi')
	if "verbose" in cargs.keys():
		print("Writing CAS XMI to " + outfile)
	cas.to_xmi(outfile)

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
	print('''Usage: python teitok2cas.py [options] FILENAME

Options:
--help         : show this help
--verbose      : verbose mode
--debug        : debug mode
--test         : print output to STDOUT
--file=FILE    : XML input filename
--outfile=FILE : XMI output filename
''')
	exit()

convert(fname)