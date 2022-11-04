import lxml.etree as etree
import sys

def getval(node, attr):
	if attr in node.keys():
		return node.attrib[attr]
	return ""

concols = ['ord', 'form', 'lemma', 'upos', 'xpos', 'feats', 'ohead', 'deprel', 'dep', 'misc']

	
def readback(filename):
	
	if "infile" in cargs.keys():
		infile = cargs["infile"]
	else:
		infile = filename.replace('.xml', '.conllu')
	if "verbose" in cargs.keys():
		print("Reading back conllu file: " + infile)
	xmlf = etree.parse(filename)

	annid = 1;
	spans = xmlf.findall("//{*}span")
	if spans is not None:
		for span in spans:
			spanid = span.get('id')
			if spanid[0:4] == "ann-":
				thisid = int(spanid[4:])
				if thisid >= annid:
					annid = thisid + 1

	nerxml = xmlf.find("//{*}spanGrp[@type=\"entities\"]")
	firstann = annid
	if nerxml is None:
		nerxml = etree.Element("spanGrp")
		nerxml.set("type", "entities")	
	
	# Deal with NameSpace if needed
	xmlns = xmlf.getroot().nsmap
	if None in xmlns.keys() and not "tei" in xmlns.keys():
		xmlns["tei"] = xmlns[None]
	if "tokxp" in cargs.keys():
		tokxp = cargs['tokxp']
		tokres = xmlf.findall(tokxp, xmlns)
	elif xmlns:
		tokxp = "//tei:text//tei:tok"
		tokres = xmlf.findall(tokxp, xmlns)
	else:
		tokxp = "//text//tok"
		tokres = xmlf.findall(tokxp)
		
	
	if "debug" in cargs.keys():
		print("Token XPath: " + tokxp)
	
	toks = {}
	nes = {}
	id2ord = {}
	ord2id = {}
	docend = -1
	for tok in tokres:
		tokid = tok.attrib['id']
		toks[tokid] = tok

	conllu = open(infile, 'r')

	# Read back the token based data
	for line in conllu:
		data = line.replace("\n", "")
		if data == "":
			# End of sentence - calculate head from ohead
			for tokid in id2ord:
				tok = toks[tokid]
				if not "ohead" in tok.attrib.keys():
					continue
				ohead = tok.attrib['ohead']
				if not ohead in ord2id.keys():
					if ohead != "0":
						print("ohead not found in sentence: " + tokid  + " => " + ohead )
					continue
				thead = ord2id[ohead]
				tok.attrib['head'] = thead
			for j in nes:
				ne = nes[j]
				if "debug" in cargs.keys():
					print("Named Entity " + j + ": " + str(ne))
				for i in ne["ords"]:
					corresp = " #" + ord2id[i]
				corresp = corresp[1:]
				annelm = nerxml.find(".//{*}span[@corresp=\""+corresp+"\"]")
				if annelm is None:
					annelm = etree.Element("span")
					annelm.set("id", "ann-"+str(annid))
					annid = annid + 1
					annelm.tail = "\n"
					nerxml.append(annelm)
				annelm.set("type", ne["type"])
				annelm.set("corresp", corresp)
			id2ord = {}
			ord2id = {}
			nes = {}
		elif data[0:1] == "#":
			# Metadata or comment line
			continue
		else:
			flds = data.split("\t")
			misc = flds[9].split('|')
			ord = flds[0]
			tokid = ""
			join = ""
			for mf in misc:
				mfa = mf.split("=")
				if mfa[0] == "tokId" or mfa[0] == "tok_id":
					# TEITOK style token ID
					tokid = mfa[1]
				if mfa[0] == "NE":
					# CoNLL-U+NE style Named Entity
					tmp = mfa[1].split("_")
					if not tmp[1] in nes.keys():
						nes[tmp[1]] = {"type": tmp[0], "ords": [ord] }
					else:
						nes[tmp[1]]["ords"].append(ord)
				elif not "=" in mf:
					# Old TEITOK style token ID
					tokid = mf
			if tokid == "":
				if "debug" in cargs.keys():
					print("Token line without a tokid: " + data)
				continue
			if not tokid in toks.keys():
				if "debug" in cargs.keys():
					print("Unknown tokid: " + tokid)
				continue
			tok = toks[tokid]
			id2ord[tokid] = ord
			ord2id[ord] = tokid
			
			# Check that this is the right word
			cform = flds[1]
			xform = tok.text
			if "form" in tok.attrib.keys():
				xform = tok.get("form")
			if cform != xform:
				print ("Verification mismatch: " + tokid + " => " + cform + " =/= " + xform)
				continue
						
			# Put back the fields
			if join != "" and "join" in cargs.keys():
				tok.set("join", join)
			cc = -1
			for conf in concols:
				cc = cc+1 
				if conf == "form":
					continue
				if flds[cc] == "" or flds[cc] == "_":
					continue
				if "debug" in cargs.keys():
					print (str(cc) + " - " + conf + " > " + flds[cc])
				tok.attrib[conf] = flds[cc]
			
			if "debug" in cargs.keys():
				print("Token " + tokid + " -> " + etree.tostring(tok, encoding='unicode', method='xml'))
		
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
--join         : add @join="right" for SpaceAfter=No
--tokxp        : XPath query for tokens
--file=FILE    : XML filename for readback
--infile=FILE  : CoNLL-U input filename
''')
	exit()

readback(fname)