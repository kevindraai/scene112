extends RefCounted
## Original adult stories; declarations are accounts, never proof of cause/guilt.
## The physical wreck, short marks and small wet patch are the same intersection.
const CASES := [
	{
		"title": "Bezorging bij de kruising",
		"people": {
			"lotte": {"source": "Maaike, bestuurder (43)", "age": 43, "position": [-19.0, 0.0, 21.0],
				"motive": "Ze vreest de reactie van haar opdrachtgever op de vertraagde bezorging.",
				"open": "Ik bracht een bestelling weg. Bij de kruising remde ik toen ik rechts beweging zag. Mijn snelheid weet ik niet precies; ik schrok van de klap.",
				"suggestive": "U zegt dat ik haast had en te hard reed. De bestelling was laat, maar mijn snelheid weet ik niet. Dat zijn twee verschillende dingen."},
			"bram": {"source": "Sven, getuige (51)", "age": 51, "position": [-16.0, 0.0, 14.5],
				"motive": "Hij wil behulpzaam zijn, maar keek eerst naar zijn telefoon.",
				"open": "Ik stond op de stoep naar mijn telefoon te kijken. Ik hoorde banden en keek pas na de klap op. De botsing zelf heb ik niet gezien.",
				"suggestive": "Als u zegt dat ze te hard reed, misschien. Ik keek alleen pas na het geluid op; een snelheid kan ik niet geven."}
		},
		"observations": {
			"damage": {"position": [-18.0, 0.0, 18.0], "text": "Ik zag beschadiging aan de rechtervoorzijde van het stilstaande voertuig."},
			"marks": {"position": [-20.0, 0.0, 15.0], "text": "Ik zag korte donkere bandensporen op het asfalt; de gereden snelheid is niet vastgesteld."},
			"road": {"position": [-20.0, 0.0, 19.2], "text": "Ik zag een plaatselijk nat stuk wegdek. De andere rijbaan bleef vrij."}
		}
	},
	{
		"title": "Schrikreactie na een parkeerbeweging",
		"people": {
			"lotte": {"source": "Jonas, bestuurder (34)", "age": 34, "position": [-19.0, 0.0, 21.0],
				"motive": "Hij wil uitleggen waarom hij stopte zonder de onbekende ander te beschuldigen.",
				"open": "Ik reed net verder na het parkeren. Ik dacht dat er iemand zou oversteken en remde. Of die persoon echt de rijbaan opkwam, weet ik niet.",
				"suggestive": "U zegt dat ik zonder kijken optrok. Ik keek wel, maar mijn herinnering aan de volgorde is na de schrik niet scherp."},
			"bram": {"source": "Fatima, getuige (62)", "age": 62, "position": [-16.0, 0.0, 14.5],
				"motive": "Ze wil precies blijven en heeft de bestuurder pas na afloop gesproken.",
				"open": "Ik kwam na het geluid naar de hoek. De auto stond toen al stil. Dat er iemand overstak hoorde ik van de bestuurder; dat heb ik niet zelf gezien.",
				"suggestive": "U noemt een overstekende voetganger. Dat heb ik alleen van hem gehoord. Ik kan niet bevestigen dat die op de rijbaan stond."}
		},
		"observations": {
			"damage": {"position": [-18.0, 0.0, 18.0], "text": "Aan de auto zag ik schade rechtsvoor; de schade alleen verklaart de toedracht niet."},
			"marks": {"position": [-20.0, 0.0, 15.0], "text": "Op het wegdek waren korte donkere bandensporen zichtbaar. Daaruit bepaalde ik geen snelheid."},
			"road": {"position": [-20.0, 0.0, 19.2], "text": "Naast het incident zag ik een natte plek op het asfalt en ruimte voor verkeer op de andere rijbaan."}
		}
	},
	{
		"title": "Bedrijfsauto op weg naar de werkplaats",
		"people": {
			"lotte": {"source": "Noor, bestuurder (46)", "age": 46, "position": [-19.0, 0.0, 21.0],
				"motive": "Ze maakt zich zorgen om de beschadigde bedrijfsauto en haar uitleg aan de werkgever.",
				"open": "Ik was onderweg naar de werkplaats. Ik remde en hoorde de klap. Ik dacht even dat de auto weggleed, maar of dat echt gebeurde weet ik niet zeker.",
				"suggestive": "Als u zegt dat de natte weg de oorzaak was, klinkt dat logisch. Ik weet alleen niet zeker of ik daadwerkelijk weggleed."},
			"bram": {"source": "Emre, getuige (29)", "age": 29, "position": [-16.0, 0.0, 14.5],
				"motive": "Hij wil helpen, maar onderscheidt wat hij hoorde van wat hij daarna zag.",
				"open": "Ik liep aan de overkant en hoorde remmen. Daarna zag ik de auto stilstaan. Ik zag de natte plek, maar niet of een band daar doorheen reed.",
				"suggestive": "U zegt dat ze over die natte plek gleed. Ik zag de plek pas toen de auto al stil stond; het wegglijden heb ik niet waargenomen."}
		},
		"observations": {
			"damage": {"position": [-18.0, 0.0, 18.0], "text": "Ik nam schade aan de rechtervoorhoek van de auto waar."},
			"marks": {"position": [-20.0, 0.0, 15.0], "text": "Ik zag korte donkere sporen van banden. Een remsnelheid is hiermee niet vastgesteld."},
			"road": {"position": [-20.0, 0.0, 19.2], "text": "Ik zag plaatselijk nat asfalt en een vrije overige rijbaan; een oorzakelijk verband is daarmee niet vastgesteld."}
		}
	}
]
