/*  
[INFO] 
NAME = Corona to VRay Converter
VERSION = 1.1.4
AUTHOR = MastaMan
DEV = https://3dground.net
HELP = 
CLIENT = RENDER.BAR
[ABOUT]
More advanced script to automatically convert scenes from Corona to VRay.=
 = 
Special for RENDER.BAR and Nazarii Derkach.=

[1.0.0]
* Initial release =

[1.0.1]
+ Added: Button Instant Convert Current Scene=
* Changed: Scene postfix name to _Vray=

[1.0.2]
* Changed: Changed Hism to Render.Bar=

[1.1.0]
+ Added: Remove all scene layers=
+ Added: Installer=
+ Added: Disable redraw viewports=
+ Added: Option Convert to V-Ray=
+ Added: Option Remove Layers=
+ Added: Option Rename Converted Scenes=
* Changed: Listbox height=

[1.1.1]
+ Added: Logging=

[1.1.2]
* Changed: Updated vrayutils.ms to VRay 6=

[1.1.3]
* Changed: Save with previews=

[1.1.4]
+ Added: Option Unlock Fresnes IOR=

[SCRIPT]
*/

struct dateTime (
    n = (dotNetClass "System.DateTime").Now,
    y = n.year as string,
    d = n.day as string,
    m = n.month as string,
    hh = n.hour as string,
    mm = n.minute as string,
    ss = n.second as string
)

fn getDate = (
	d = dateTime()	
	return d.d + "." + d.m + "." + d.y
)

fn boost = (
	if (((maxVersion())[1] / 1000) >= 13) do windows.processPostedMessages() 
)

fn formatString s v: #() tag: "$"= (
	for i in 1 to v.count  do (
		s = substituteString s (tag + i as string) (v[i] as string)
	)
	
	return s
)

fn getFileMb f = (
	if (not doesFileExist f) do return 0.0
	s = (getFileSize f) / 1048576.0
	return ((s * 100) as integer) / 100.0
)

fn trimString s tag: "" = (
	s = s as string
	return (trimLeft (trimRight s tag) tag)
)

fn isCanOpenMaxFile f = (
	local fv = try ((getMaxFileVersionData f)[1]) catch (undefined)
	local mv = (maxVersion())[1]
	
	if (fv == undefined) do return false
	
	return fv <= mv
)

fn removeLayers = (
	layer0 = LayerManager.getLayer 0
	layer0.current = true
	for i in objects do layer0.addNode i
	
	try (
		for l in layerManager.count to 2 by -1 do (
			la = layerManager.getLayer (l - 1)
			
			n = undefined
			la.nodes &n
			
			if (n.count == 0) do (
				layerManager.deleteLayerByName la.name
			)
		)
	) catch ()
)

fn freezeUi = (
    source = ""
    source += "using System;\n"
    source += "using System.Runtime.InteropServices;\n"
    source += "class WindowsGhosting\n"
    source += "{\n"
    source += " [DllImport(\"user32.dll\")]\n"
    source += " public static extern void DisableProcessWindowsGhosting();\n"
    source += "}\n"
  
    csharpProvider = dotnetobject "Microsoft.CSharp.CSharpCodeProvider"
    compilerParams = dotnetobject "System.CodeDom.Compiler.CompilerParameters"
  
    compilerParams.GenerateInMemory = on
    compilerResults = csharpProvider.CompileAssemblyFromSource compilerParams #(source)
  
    assembly = compilerResults.CompiledAssembly
    windowsGhosting = assembly.CreateInstance "WindowsGhosting"
    windowsGhosting.DisableProcessWindowsGhosting()
)

struct settingsWrapper (
    pth = getFilenamePath (getThisScriptFilename()),
    settingsFile = pth + @"settings.ini",
    fn s k v ss: "SETTINGS" = (
        setINISetting settingsFile ss k (v as string)
    ),
    fn g k type: #string  ss: "SETTINGS" = (
        local s = getINISetting settingsFile ss k
        case type of (
            #int: return s as integer
            #float: return s as float
            #bool: if s == "true" or s.count < 1 then true else false
            #bool_not: if s == "true" then true else false
            
            default: return s
        )
    ),
    fn a ss: "SETTINGS" type: #string = (
        local s = getINISetting settingsFile ss
        local o = #()
        
        for k in s do (
            local v = g k ss: ss type: type
            append o #(k, v)
        )
        
        return o
    ),
    fn d k ss: "SETTINGS" = (
        delIniSetting settingsFile ss k
    )
)

'@' = settingsWrapper()

try(closeRolloutFloater _fCorona2VRayConverter) catch()
global _fCorona2VRayConverter = newRolloutFloater "" 300 720

rollout _rCorona2VRayConverter_Main "Main" (
	local postfix = "_Vray"
	local dataList = #()
	
	group "Select Directory" (
		edittext edtInputPath "" readonly: true across: 2 align: #left fieldwidth: 215 height: 22		
        button btnSearchPath "..." width: 35 height: 24  align: #right offset: [0, -1]
	)
		
	group "Scenes" (	
		label lblTotalCaptin "Total " align: #left across: 2
		label lblTotalCnt ": (0)" align: #left across: 2 offset: [-104, 0]		
		label lblSelectedFor "Selected for Conversion " align: #left across: 2
		label lblSelectedForCnt ": (0)" align: #left across: 2 offset: [-15, 0]
		
		multiListBox lbxScenes "" items: #() height: 25
		
		label lblDummy1 "" height: 3
		button btnSelectAll "Select All" width: 100 across: 2
		button btnDeselectAll "Deselect All" width: 100
		
		progressBar pbProgress "" height: 6 color: orange value: 0 offset: [0, 5]
		label lblStatus "" align: #left offset: [0, 5]
		
		checkbox cbxRenameConvertedScenes "Rename Converted Scenes" checked: true
		checkbox cbxConvertToVray "Convert to V-Ray" checked: true
		checkbox cbxRemoveLayers "Remove Layers" checked: true
		checkbox cbxUnlockFresnel "Unlock Fresnes IOR" checked: true
		
		button btnStartBatchConvert "Convert" width: 260 height: 32 enabled: false
		button btnStartInstantConvert "Instant Convert Current Scene" width: 260 height: 22
	)
	
	fn toggleUi s = (
		lbxScenes.enabled = s
		btnSelectAll.enabled = s
		btnDeselectAll.enabled = s
		btnStartBatchConvert.enabled = s
		btnStartInstantConvert.enabled = s
	)
	
	fn getData = (
		dataList = #()
		
		local p = edtInputPath.text
		if (p == "") do (
			return dataList
		)
		
		local items = #()
		
		for i in getFiles (p + "*.max") where (isCanOpenMaxFile i) do (			
			if (findString i postfix != undefined) do continue
			
			struct data (file, name, path, status, ext)
			append dataList (data file: i name: (getFileNameFile i) path: (getFilenamePath i) status: "" ext: ".max")
		)
		
		return dataList
	)
	
	fn updateList = (		
		local items = for i in dataList collect i.status + i.name
		
		lbxScenes.items = items
		lblTotalCnt.caption = formatString ": ($1)" v: #(items.count)
		local ss = lbxScenes.selection as array
		btnStartBatchConvert.enabled = items.count != 0 and ss.count != 0		
	)
	
	fn updateLbx = (
		local ss = lbxScenes.selection as array
		local i = ss.count
		btnStartBatchConvert.enabled = i > 0
		lblSelectedForCnt.caption = ": (" + (i as string) + ")"
		btnStartBatchConvert.caption = "Convert (" + (i as string) + ")"
	)
	
	fn launchVRayUtils = (
		local p = getFilenamePath (getThisScriptFilename())
		local f = p + "vrayutils.ms"
			
		if (doesFileExist f) do (
			fileIn f
			return true
		)
		
		messageBox "Script \"vrayutils.ms\" not found in Vray to Corona Converter folder!" title: "Error!"
		return false
	)
	
	fn chageRenderToVRay = (
		try (renderers.current = VRay()) catch (return false)
		return true
	)
	
	fn startVRayConvert = (
		CreateDialog vraySceneConverterRollout
		vraySceneConverterRollout.visible = false
		vraySceneConverterRollout.check_optConvertPhysicalMtl.checked = true
		vraySceneConverterRollout.btn_convertStart.pressed()
	)
	
	fn fixVray2SidedMtl = (
		for i in (getClassInstances VRay2SidedMtl) do (
			if (i.backMtl != undefined) do (
				i.backMtl = i.frontMtl			
				i.texmap_translucency = undefined
			)
		)
	)
	
	fn postSetupVRayMtl = (
		for i in (getClassInstances VRayMtl) do (
			-- Disable button L
			if (cbxUnlockFresnel.checked) do i.reflection_lockIOR = false
		)
	)
		
	fn convertScene = (		
		with redraw off (
			if (cbxConvertToVray.checked) do (			
				launchVRayUtils()
				chageRenderToVRay()
				try (startVRayConvert()) catch (return false)
				fixVray2SidedMtl()
				postSetupVRayMtl()
			)
			
			if (cbxRemoveLayers.checked) do (
				removeLayers()
			)
		)
		
		return true
	)
	
	fn runInstantConvert = (
		local isVRayUtilsExist = launchVRayUtils()
		if (not isVRayUtilsExist) do return false
		
		convertScene()
	)
	
	fn runBatchConvert = (
		if (not cbxConvertToVray.checked and not cbxRemoveLayers.checked) do (
			local m = "Please select at least one option: \n\n* Convert to V-Ray\n* Remove Layers"
			return messageBox m title: "Warning!"
		)
		
		local date = getDate()
		local iniPath = edtInputPath.text
		local iniLog = iniPath + "log.txt"
		
		local isVRayUtilsExist = launchVRayUtils()
		if (not isVRayUtilsExist) do return false

		local ss = lbxScenes.selection as array
		
		getData()
		
		local items = dataList
		local iterator = 0
		local statusMsg = "Progress: $1/$2 ($3%) | $4 left | Selected $2 from $5"
		lblStatus.caption = formatString statusMsg v: #(iterator + 1, ss.count, pbProgress.value, ss.count - iterator, items.count)
		
		toggleUi false
		
		for id in ss do (
			iterator += 1
			
			local i = items[id]
			if (i == undefined) do continue
			
			resetMaxFile #noPrompt
			loadMaxFile i.file useFileUnits: true quiet:true
			
			local r = convertScene()
			if (r) then (
				i.status = "[OK] "
				
				local p = i.path
				local n = i.name
				n = substituteString n postfix ""
				local ext = i.ext
				
				local newName = i.file
				
				if (cbxRenameConvertedScenes.checked) do (
					newName = p + n + postfix + ext
				)
				
				saveMaxFile newName quiet: true
				
				max tool zoomextents all
				max views redraw
				
				max file save
				
				setINISetting iniLog date (i.status + i.name) i.file
				
			) else (
				i.status = "[ERROR] "
				
				setINISetting iniLog date (i.status + i.name) i.file
			)
			
			pbProgress.value = (100.0 * iterator / ss.count)
			lblStatus.caption = formatString statusMsg v: #(iterator, ss.count, pbProgress.value, ss.count - iterator, items.count)
			
			updateList()
			boost()
		)
		
		resetMaxFile #noPrompt
		
		toggleUi true
		
		updateList()
		updateLbx()
		
		ShellLaunch (edtInputPath.text) ""
	)
	
	fn loadSettings = (
		-- Global path
		local p = '@'.g "PATH"
		if (p != "" and doesDirectoryExist p) do edtInputPath.text = p
		
		cbxConvertToVray.checked = '@'.g "CONVERT_TO_VRAY" type: #bool
		cbxRemoveLayers.checked = '@'.g "REMOVE_LAYERS" type: #bool
		cbxRenameConvertedScenes.checked = '@'.g "RENAME_SCENES" type: #bool
		cbxUnlockFresnel.checked = '@'.g "UNLOCK_FRESNEL_IOR" type: #bool_not
	)
	
	on cbxConvertToVray changed v do (
		'@'.s "CONVERT_TO_VRAY" v
	)
	
	on cbxRemoveLayers changed v do (
		'@'.s "REMOVE_LAYERS" v
	)
	
	on cbxRenameConvertedScenes changed v do (
		'@'.s "RENAME_SCENES" v
	)
	
	on cbxUnlockFresnel changed v do (
		'@'.s "UNLOCK_FRESNEL_IOR" v
	)
	
	on lbxScenes selectionEnd do (
		updateLbx()
	)
	
	on btnDeselectAll pressed do (
		lbxScenes.selection = #{}
		updateLbx()
	)
	
	on btnSelectAll pressed do (		
		lbxScenes.selection = for i in 1 to lbxScenes.items.count collect i
		updateLbx()
	)
	
	on btnStartBatchConvert pressed do (
		runBatchConvert()
	)
	
	on btnStartInstantConvert pressed do (
		runInstantConvert()
	)
	
	on btnSearchPath pressed do (
		local p = getSavePath()
		
		if (p == undefined) do return false
		p += @"\"
		
		edtInputPath.text = p
		'@'.s "PATH" p
		
		getData()
		updateList()
		updateLbx()
	)
	
	on _rCorona2VRayConverter_Main open do (
		launchVRayUtils()
		
		freezeUi()
		loadSettings()
		getData()
		updateList()
	)
)

rollout _rCorona2VRayConverter_About "About" (
	label lblDummy1 ""
    
	label lblName "" 
	label lblVer ""
	label lblClient ""
	
	label lblDummy2 ""
	
	label lblAuthor ""
	hyperlink lblCopy ""  align: #center
	
	label lblDummy3 ""
	
	group "Description" (
		dotNetControl edtDescription "System.Windows.Forms.Textbox" align:#center height: 300
	)
	
	
	timer tmrRestart "" active: false interval: 300
	    
	fn downloadFile url dl = (
		deleteFile dl
		w = dotNetObject "System.Net.WebClient"			
		try(
			spm = dotNetClass "System.Net.ServicePointManager"
			spm.SecurityProtocol = spm.SecurityProtocol.TLS12				
			w.DownloadFile (url + "?time=" + timestamp() as string) dl				
		) catch(
			return false
		)
		
		return true
	)
	
	fn bgUpdate = (
		local url = "https://raw.githubusercontent.com/MastaArt/RENDERBAR-Vray2Corona-Converter/main/"
		
		local files = #(
			"vrayutils.ms",
			"Install-Vray2Corona-Converter.mcr"
		)
		
		this = getThisScriptFileName()
		dl = this + ".tmp"
		p = getFilenamePath this
		r = downloadFile (url + "Vray2Corona-Converter.ms") dl
		if(not r or not doesFileExist dl) do return print "Can't download updates!"
		vn = getIniSetting dl "INFO" "VERSION"
		vo = getIniSetting this "INFO" "VERSION"
		
		if(vn > vo) do (
			deleteFile this
			renameFile dl this
			
			for f in files do (				
				downloadFile (url + f) (p + f)
			)
			
			tmrRestart.active = true
		)
		
		deleteFile dl
	)
	
	fn updateWorker = (
		m = dotnetobject "CSharpUtilities.SynchronizingBackgroundWorker"
		m.WorkerSupportsCancellation = true 
		m.CancelAsync() 
		dotNet.addEventHandler m "DoWork" bgUpdate
		m.RunWorkerAsync()	
	)
	
    fn getScriptInfo s releaseInfo: "" =  (
        if(releaseInfo != "") do (
            local r = getINISetting s releaseInfo
            return r
        )
		
        local v = getINISetting s "INFO" "VERSION"
        local a = getINISetting s "INFO" "AUTHOR"
        local n = getINISetting s "INFO" "NAME"
        local o = ""
		for i in (getINISetting s "ABOUT") do o += i + "\r\n"
        local d = getINISetting s "INFO" "DEV"
        local h = getINISetting s "INFO" "HELP"
        local c = getINISetting s "INFO" "CLIENT"
        
		struct data (version, author, name, description, developer, client, help, releases)
		
        local r = for i in (getINISetting s) where (i != "INFO" and i != "ABOUT" and i != "SCRIPT" and i != "COPY") collect i
		
		return (data version: v author: a name: n description: o developer: d client: c help: h releases: r)
    )
	
	on tmrRestart tick do (
		this = getThisScriptFileName()
		try(fileIn this) catch()
		vo = getIniSetting this "INFO" "VERSION"
		m = ("Script updated to version " + vo + "!\n\n\n")
		for c in (getIniSetting this vo) do (
			m += c + "\n"
		)
		
		messageBox m title: "Success!" beep: false
		tmrRestart.active = false
	)

    on _rCorona2VRayConverter_About open do (
		edtDescription.MultiLine = true
		edtDescription.WordWrap = true
		edtDescription.ReadOnly = true
		edtDescription.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").FixedSingle
		edtDescription.ScrollBars = (dotNetClass "System.Windows.Forms.ScrollBars").Vertical
		
		local thisScript = getThisScriptFilename()
        local i = getScriptInfo thisScript
		
        lblName.caption = i.name
        lblAuthor.caption = i.author
        lblVer.caption = i.version
        lblCopy.address = lblCopy.caption = i.developer
        lblClient.caption = i.client
		edtDescription.text = i.description
			
			
		local releaseNotes = ""	
		for ii in i.releases.count to 1 by -1 do (
			local v = i.releases[ii]
			local r = getScriptInfo thisScript releaseInfo: v
			
			releaseNotes += "\r\n" + v + "\r\n"
			for j in r do releaseNotes += j + "\r\n"
		)
		
		edtDescription.text += releaseNotes
		
		try (_fCorona2VRayConverter.title = i.client) catch()
		try (_rCorona2VRayConverter_Main.title = i.name + " v" +  i.version) catch()
		
		--updateWorker()
    )		
)

addRollout _rCorona2VRayConverter_Main _fCorona2VRayConverter rolledUp: false
addRollout _rCorona2VRayConverter_About _fCorona2VRayConverter rolledUp: true