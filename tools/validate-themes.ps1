[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$errors = [Collections.Generic.List[string]]::new()
$ids = @{}
$images = @('.png','.jpg','.jpeg'); $audio = @('.wav','.mp3','.wma'); $fonts = @('.ttf','.otf')
$allowed = @('.json','.png','.jpg','.jpeg','.ttf','.otf','.wav','.mp3','.wma','.txt','.md')

function Fail($theme, $message) { $script:errors.Add("${theme}: $message") }
function Rule($kind, $min = $null, $max = $null, $values = $null, $asset = $null) {
    [pscustomobject]@{ Kind=$kind; Min=$min; Max=$max; Values=$values; Asset=$asset }
}
function Put($map, $name, $kind, $min = $null, $max = $null, $values = $null, $asset = $null) {
    $map[$name] = Rule $kind $min $max $values $asset
}
function SafeFile($theme, $folder, $property, $value, $extensions) {
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) { Fail $theme "$property must be a non-empty relative path"; return $false }
    if ([IO.Path]::IsPathRooted($value)) { Fail $theme "$property must be relative"; return $false }
    try {
        $root = [IO.Path]::GetFullPath($folder.FullName).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $path = [IO.Path]::GetFullPath((Join-Path $folder.FullName $value))
        if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { Fail $theme "$property escapes the design folder"; return $false }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail $theme "$property references missing file '$value'"; return $false }
        if ($extensions -notcontains [IO.Path]::GetExtension($path).ToLowerInvariant()) { Fail $theme "$property has an unsupported file type"; return $false }
        return $true
    } catch { Fail $theme "$property has an invalid path"; return $false }
}
function StringArray($theme, $name, $value) {
    if ($value -is [string] -or -not ($value -is [Collections.IEnumerable])) { Fail $theme "$name must be an array of strings"; return }
    $seen=@{}; foreach ($item in @($value)) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) { Fail $theme "$name contains an invalid value" }
        elseif ($seen.ContainsKey($item)) { Fail $theme "$name contains duplicate '$item'" } else { $seen[$item]=$true }
    }
}
function Appearance($theme, $folder, $file, $rules, $fontIds) {
    $path=Join-Path $folder.FullName $file
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { $doc=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { Fail $theme "$file is invalid JSON: $($_.Exception.Message)"; return $null }
    if ($null -eq $doc -or $doc -is [array]) { Fail $theme "$file must contain one JSON object"; return $null }
    foreach ($p in $doc.PSObject.Properties) {
        if (-not $rules.ContainsKey($p.Name)) { Fail $theme "$file contains unknown property '$($p.Name)'"; continue }
        $r=$rules[$p.Name]; $v=$p.Value
        switch ($r.Kind) {
            'bool' { if ($v -isnot [bool]) { Fail $theme "$($p.Name) must be a boolean" } }
            'int' { if ($v -isnot [int] -and $v -isnot [long]) { Fail $theme "$($p.Name) must be an integer" } elseif ([long]$v -lt $r.Min -or [long]$v -gt $r.Max) { Fail $theme "$($p.Name) must be between $($r.Min) and $($r.Max)" } }
            'enum' { if ($v -isnot [string] -or $r.Values -notcontains $v) { Fail $theme "$($p.Name) must be one of: $($r.Values -join ', ')" } }
            'color' { if ($v -isnot [string] -or $v -notmatch '^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$') { Fail $theme "$($p.Name) must be #RRGGBB or #AARRGGBB" } }
            'font' { if ($v -isnot [string] -or [string]::IsNullOrWhiteSpace($v) -or $v.Length -gt 200) { Fail $theme "$($p.Name) must be a font name or `$font:<Id>" } elseif ($v.StartsWith('$font:',[StringComparison]::OrdinalIgnoreCase) -and -not $fontIds.ContainsKey($v.Substring(6))) { Fail $theme "$($p.Name) references unknown font '$($v.Substring(6))'" } }
            'image' { [void](SafeFile $theme $folder $p.Name $v $images) }
            'order' { $parts=if ($v -is [string]) {@($v.Split(',')|%{$_.Trim()})} else {@()}; $classic=@('Title','Controller','Metadata','Instruction','Status');$alert=@('Incident','Title','ControllerName','Metadata','Instruction','Status');$valid=(@($parts|sort -Unique).Count-eq$parts.Count)-and((($parts.Count-eq$classic.Count)-and-not@($parts|?{$classic-notcontains$_}).Count)-or(($parts.Count-eq$alert.Count)-and-not@($parts|?{$alert-notcontains$_}).Count));if(-not$valid){Fail $theme "$($p.Name) must contain every classic or alert-layout block exactly once"} }
        }
    }
    return $doc
}

$nr=@{}
$nd=@(
 @('Width','int',300,900),@('ScalePercent','int',80,160),@('DurationMilliseconds','int',2000,15000),@('Position','enum',$null,$null,@('TopRight','TopLeft','BottomRight','BottomLeft')),@('ScreenMargin','int',8,64),@('Animation','enum',$null,$null,@('None','Fade','FadeScale','Slide')),@('ShowShadow','bool'),
 @('Padding','int',0,40),@('ElementSpacing','int',0,40),@('IconSpacing','int',0,40),@('IconPosition','enum',$null,$null,@('Left','Right','Top','Bottom')),@('IconSize','int',20,96),@('TextAlignment','enum',$null,$null,@('Left','Center','Right')),@('TextOrder','enum',$null,$null,@('TitleFirst','MessageFirst')),@('MessageMaxLines','int',1,6),@('ShowTitle','bool'),@('UppercaseTitle','bool'),
 @('FontFamily','font'),@('FontWeight','enum',$null,$null,@('Regular','SemiBold','Bold')),@('TitleFontFamily','font'),@('TitleFontWeight','enum',$null,$null,@('Regular','SemiBold','Bold')),@('TitleFontSize','int',10,48),@('MessageFontFamily','font'),@('MessageFontWeight','enum',$null,$null,@('Regular','SemiBold','Bold')),@('MessageFontSize','int',10,36),
 @('BackgroundColor','color'),@('UseGradient','bool'),@('GradientColor','color'),@('GradientAngle','int',0,359),@('TextColor','color'),@('SecondaryTextColor','color'),@('ConnectedColor','color'),@('DisconnectedColor','color'),@('WarningColor','color'),@('LowBatteryColor','color'),@('UseStateBackgroundColors','bool'),@('ConnectedBackgroundColor','color'),@('DisconnectedBackgroundColor','color'),@('WarningBackgroundColor','color'),@('LowBatteryBackgroundColor','color'),@('AccentMode','enum',$null,$null,@('IconAndBorder','IconOnly','TintedBackground','SolidBackground')),
 @('UseBackgroundImage','bool'),@('BackgroundImagePath','image'),@('BackgroundImageStretch','enum',$null,$null,@('UniformToFill','Uniform','Fill')),@('BackgroundImageHorizontalAlignment','enum',$null,$null,@('Left','Center','Right')),@('BackgroundImageVerticalAlignment','enum',$null,$null,@('Top','Center','Bottom')),@('BackgroundImageOpacity','int',0,100),@('BackgroundImageTintOpacity','int',0,100),
 @('ShowIconContainer','bool'),@('IconContainerColor','color'),@('IconContainerBorderColor','color'),@('IconContainerBorderThickness','int',0,8),@('IconContainerCornerRadius','int',0,40),@('IconContainerPadding','int',0,24),@('ShowConnectionBadge','bool'),@('BadgePosition','enum',$null,$null,@('TopLeft','TopRight')),
 @('ShowBorder','bool'),@('BorderPosition','enum',$null,$null,@('Left','Top','Right','Bottom','Full')),@('BorderThickness','int',0,10),@('CornerRadius','int',0,40),@('UseIndependentBorders','bool'),@('BorderLeftThickness','int',0,12),@('BorderTopThickness','int',0,12),@('BorderRightThickness','int',0,12),@('BorderBottomThickness','int',0,12),@('UseBorderGradient','bool'),@('UseStateBorderColors','bool'),@('ConnectedBorderColor','color'),@('DisconnectedBorderColor','color'),@('WarningBorderColor','color'),@('LowBatteryBorderColor','color'),@('BorderGradientStartColor','color'),@('BorderGradientEndColor','color'),@('BorderGradientAngle','int',0,359),@('ShowBorderGlow','bool'),@('BorderGlowColor','color'),@('BorderGlowBlur','int',0,40),@('BorderGlowOpacity','int',0,100)
)
foreach($prefix in @('Notification','DesktopNotification')){foreach($d in $nd){Put $nr ($prefix+$d[0]) $d[1] $d[2] $d[3] $d[4]}}
Put $nr 'ShowControllerNameInNotifications' 'bool'; Put $nr 'ShowControllerNameInDesktopNotifications' 'bool'

$or=@{}
$od=@(
 @('ScalePercent','int',80,140),@('CardWidth','int',320,1000),@('CardPosition','enum',$null,$null,@('Center','Top','Bottom','TopLeft','TopRight','BottomLeft','BottomRight')),@('ScreenMargin','int',0,160),@('LayoutMode','enum',$null,$null,@('Standard','Split','Hero','Alert')),@('ContentAlignment','enum',$null,$null,@('Left','Center','Right')),@('Animation','enum',$null,$null,@('None','Fade','FadeScale','Slide')),@('BlockOrder','order'),@('MetadataOrientation','enum',$null,$null,@('Horizontal','Vertical')),@('Padding','int',12,80),@('ElementSpacing','int',0,48),
 @('ShowTitle','bool'),@('UppercaseTitle','bool'),@('ShowInstruction','bool'),@('ShowPauseStatus','bool'),@('ShowControllerName','bool'),@('ShowControllerIcon','bool'),@('ShowStatusIcon','bool'),@('ShowConnectionBadge','bool'),@('ShowBatteryBadge','bool'),@('ControllerIconPosition','enum',$null,$null,@('Left','Center','Right','Top')),@('ControllerIconSize','int',16,96),@('StatusIconSize','int',12,64),
 @('DimColor','color'),@('CardColor','color'),@('UseGradient','bool'),@('GradientColor','color'),@('GradientAngle','int',0,359),@('AccentColor','color'),@('InstructionColor','color'),@('ControllerIconColor','color'),@('TextColor','color'),@('WarningColor','color'),@('UseBackgroundImage','bool'),@('BackgroundImagePath','image'),@('BackgroundImageStretch','enum',$null,$null,@('UniformToFill','Uniform','Fill')),@('BackgroundImageHorizontalAlignment','enum',$null,$null,@('Left','Center','Right')),@('BackgroundImageVerticalAlignment','enum',$null,$null,@('Top','Center','Bottom')),@('BackgroundImageOpacity','int',0,100),@('BackgroundImageTintOpacity','int',0,100),
 @('SceneUseGradient','bool'),@('SceneGradientColor','color'),@('SceneGradientAngle','int',0,359),@('SceneUseBackgroundImage','bool'),@('SceneBackgroundImagePath','image'),@('SceneBackgroundImageStretch','enum',$null,$null,@('UniformToFill','Uniform','Fill')),@('SceneBackgroundImageHorizontalAlignment','enum',$null,$null,@('Left','Center','Right')),@('SceneBackgroundImageVerticalAlignment','enum',$null,$null,@('Top','Center','Bottom')),@('SceneBackgroundImageOpacity','int',0,100),@('SceneUseAmbientGlows','bool'),@('SceneGlow1Color','color'),@('SceneGlow1X','int',0,100),@('SceneGlow1Y','int',0,100),@('SceneGlow1Radius','int',10,100),@('SceneGlow2Color','color'),@('SceneGlow2X','int',0,100),@('SceneGlow2Y','int',0,100),@('SceneGlow2Radius','int',10,100),@('SceneGlow3Color','color'),@('SceneGlow3X','int',0,100),@('SceneGlow3Y','int',0,100),@('SceneGlow3Radius','int',10,100),@('SceneShowGrid','bool'),@('SceneGridColor','color'),@('SceneGridSize','int',12,160),
 @('SplitControllerSide','enum',$null,$null,@('Left','Right')),@('ShowSplitDivider','bool'),@('SplitDividerColor','color'),@('SplitDividerThickness','int',0,8),@('ShowIncidentBadge','bool'),@('IncidentBadgeTextColor','color'),@('IncidentBadgeBackgroundColor','color'),@('IncidentBadgeBorderColor','color'),@('IncidentBadgeBorderThickness','int',0,8),@('IncidentBadgeCornerRadius','int',0,24),@('IncidentBadgeTextSize','int',9,30),@('StatusInMetadata','bool'),
 @('FontFamily','font'),@('FontWeight','enum',$null,$null,@('Regular','SemiBold','Bold')),@('TitleFontFamily','font'),@('TitleFontWeight','enum',$null,$null,@('Regular','SemiBold','Bold')),@('TitleFontSize','int',16,52),@('ControllerFontFamily','font'),@('ControllerFontWeight','enum',$null,$null,@('Regular','SemiBold','Bold')),@('ControllerFontSize','int',12,36),@('InstructionFontFamily','font'),@('InstructionFontWeight','enum',$null,$null,@('Regular','SemiBold','Bold')),@('InstructionFontSize','int',10,30),@('StatusFontFamily','font'),@('StatusFontWeight','enum',$null,$null,@('Regular','SemiBold','Bold')),@('StatusFontSize','int',10,28),
 @('ShowControllerContainer','bool'),@('ControllerContainerColor','color'),@('ControllerContainerBorderColor','color'),@('ControllerContainerBorderThickness','int',0,8),@('ControllerContainerCornerRadius','int',0,40),@('ControllerContainerPadding','int',0,32),
 @('ConnectionBadgeTextColor','color'),@('ConnectionBadgeIconColor','color'),@('ConnectionBadgeBackgroundColor','color'),@('ConnectionBadgeBorderColor','color'),@('ConnectionBadgeBorderThickness','int',0,8),@('ConnectionBadgeCornerRadius','int',0,32),@('ConnectionBadgeIconSize','int',8,40),@('ConnectionBadgeTextSize','int',8,28),@('BatteryBadgeTextColor','color'),@('BatteryBadgeIconColor','color'),@('BatteryBadgeBackgroundColor','color'),@('BatteryBadgeBorderColor','color'),@('BatteryBadgeBorderThickness','int',0,8),@('BatteryBadgeCornerRadius','int',0,32),@('BatteryBadgeIconSize','int',8,40),@('BatteryBadgeTextSize','int',8,28),@('BatteryBadgeUseStateColors','bool'),@('BatteryBadgeFullColor','color'),@('BatteryBadgeMediumColor','color'),@('BatteryBadgeLowColor','color'),@('BatteryBadgeEmptyColor','color'),
 @('ShowBorder','bool'),@('BorderPosition','enum',$null,$null,@('Left','Top','Right','Bottom','Full')),@('BorderThickness','int',0,12),@('CornerRadius','int',0,40),@('ShowShadow','bool'),@('UseIndependentBorders','bool'),@('BorderLeftThickness','int',0,12),@('BorderTopThickness','int',0,12),@('BorderRightThickness','int',0,12),@('BorderBottomThickness','int',0,12),@('UseBorderGradient','bool'),@('BorderGradientStartColor','color'),@('BorderGradientEndColor','color'),@('BorderGradientAngle','int',0,359),@('ShowBorderGlow','bool'),@('BorderGlowColor','color'),@('BorderGlowBlur','int',0,40),@('BorderGlowOpacity','int',0,100)
)
foreach($d in $od){Put $or ('Overlay'+$d[0]) $d[1] $d[2] $d[3] $d[4]}

$themeRoot=Join-Path $Root 'themes'; if(-not(Test-Path $themeRoot)){throw "Missing themes directory"}
Get-ChildItem $themeRoot -Directory | % {
    $folder=$_; $theme=$_.Name; $mp=Join-Path $_.FullName 'manifest.json'
    if(-not(Test-Path $mp)){Fail $theme 'missing manifest.json';return}
    try{$m=Get-Content $mp -Raw|ConvertFrom-Json}catch{Fail $theme "invalid manifest.json: $($_.Exception.Message)";return}
    $manifestKeys=@('SchemaVersion','Id','Name','Author','Version','MinimumPluginVersion','MaximumPluginVersion','Description','RecommendedTheme','ThemeIds','DesktopThemeIds','FullscreenThemeIds','Fonts','Sounds')
    foreach($p in $m.PSObject.Properties){if($manifestKeys -notcontains $p.Name){Fail $theme "manifest.json contains unknown property '$($p.Name)'"}}
    if(($m.SchemaVersion -isnot [int] -and $m.SchemaVersion -isnot [long]) -or $m.SchemaVersion -ne 1){Fail $theme 'SchemaVersion must be integer 1'}
    if($m.Id -isnot [string] -or $m.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$'){Fail $theme 'invalid Id'}elseif($m.Id -cne $theme){Fail $theme 'folder name must exactly match Id'}elseif($ids.ContainsKey($m.Id)){Fail $theme 'duplicate Id'}else{$ids[$m.Id]=$true}
    foreach($required in 'Name','Author','Version','MinimumPluginVersion'){if($m.$required -isnot [string] -or [string]::IsNullOrWhiteSpace($m.$required)){Fail $theme "missing or invalid $required"}}
    $v=$null;if(-not[version]::TryParse([string]$m.Version,[ref]$v)){Fail $theme 'invalid Version'};if(-not[version]::TryParse([string]$m.MinimumPluginVersion,[ref]$v)){Fail $theme 'invalid MinimumPluginVersion'};if($m.MaximumPluginVersion -and -not[version]::TryParse([string]$m.MaximumPluginVersion,[ref]$v)){Fail $theme 'invalid MaximumPluginVersion'}
    foreach($a in 'ThemeIds','DesktopThemeIds','FullscreenThemeIds'){if($null-ne$m.$a){StringArray $theme $a $m.$a}}
    $fontIds=@{};foreach($f in @($m.Fonts)){
        if($null-eq$f){continue};foreach($p in $f.PSObject.Properties){if(@('Id','Name','Family','Folder')-notcontains$p.Name){Fail $theme "font contains unknown property '$($p.Name)'"}}
        if($f.Id-isnot[string]-or$f.Id-notmatch'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'){Fail $theme 'font has invalid Id';continue};if($fontIds.ContainsKey($f.Id)){Fail $theme "duplicate font Id '$($f.Id)'";continue};$fontIds[$f.Id]=$true
        if($f.Family-isnot[string]-or[string]::IsNullOrWhiteSpace($f.Family)){Fail $theme "font '$($f.Id)' requires Family"};$ff=if([string]::IsNullOrWhiteSpace($f.Folder)){'Fonts'}else{[string]$f.Folder}
        if([IO.Path]::IsPathRooted($ff)){Fail $theme "font '$($f.Id)' Folder must be relative"}else{try{$root=[IO.Path]::GetFullPath($folder.FullName).TrimEnd('\')+'\';$fp=[IO.Path]::GetFullPath((Join-Path $folder.FullName $ff));if(-not$fp.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)-or-not(Test-Path $fp)){Fail $theme "font '$($f.Id)' Folder is missing or unsafe"}elseif(-not@(Get-ChildItem $fp -File|?{$fonts-contains$_.Extension.ToLowerInvariant()}).Count){Fail $theme "font '$($f.Id)' Folder contains no supported fonts"}}catch{Fail $theme "font '$($f.Id)' Folder is invalid"}}
    }
    if($null-ne$m.Sounds){foreach($s in $m.Sounds.PSObject.Properties){if(@('Connected','Disconnected','Warning','LowBattery')-notcontains$s.Name){Fail $theme "unknown sound '$($s.Name)'"}else{[void](SafeFile $theme $folder "Sounds.$($s.Name)" $s.Value $audio)}}}
    $n=Appearance $theme $folder 'notification.json' $nr $fontIds;$o=Appearance $theme $folder 'overlay.json' $or $fontIds
    if($null-eq$n-and$null-eq$o){Fail $theme 'notification.json or overlay.json is required'}
    if($null-ne$n){if(($n.NotificationUseBackgroundImage-eq$true-and[string]::IsNullOrWhiteSpace($n.NotificationBackgroundImagePath))-or($n.DesktopNotificationUseBackgroundImage-eq$true-and[string]::IsNullOrWhiteSpace($n.DesktopNotificationBackgroundImagePath))){Fail $theme 'enabled notification images require BackgroundImagePath'};foreach($preview in 'notification-desktop.png','notification-fullscreen.png'){if(-not(Test-Path (Join-Path (Join-Path $Root "previews\$theme") $preview))){Fail $theme "missing preview $preview"}}}
    if($null-ne$o){if($o.OverlayUseBackgroundImage-eq$true-and[string]::IsNullOrWhiteSpace($o.OverlayBackgroundImagePath)){Fail $theme 'enabled overlay image requires BackgroundImagePath'};if($o.OverlaySceneUseBackgroundImage-eq$true-and[string]::IsNullOrWhiteSpace($o.OverlaySceneBackgroundImagePath)){Fail $theme 'enabled overlay scene image requires SceneBackgroundImagePath'};if(-not(Test-Path (Join-Path (Join-Path $Root "previews\$theme") 'overlay.png'))){Fail $theme 'missing preview overlay.png'}}
    $binary=$false;Get-ChildItem $folder.FullName -Recurse -File|%{$rel=$_.FullName.Substring($folder.FullName.Length+1);$ext=$_.Extension.ToLowerInvariant();if($_.Length-gt12MB){Fail $theme "$rel exceeds 12 MB"};if($allowed-notcontains$ext-and$_.Name-ne'LICENSE'){Fail $theme "forbidden file type in $rel"};if($rel.Split('\').Count-gt8){Fail $theme "path nesting too deep in $rel"};if(($images+$audio+$fonts)-contains$ext){$binary=$true}}
    if($binary-and-not(Test-Path (Join-Path $folder.FullName 'CREDITS.md'))-and-not(Test-Path (Join-Path $folder.FullName 'LICENSE'))-and-not(Test-Path (Join-Path $folder.FullName 'LICENSE.txt'))){Fail $theme 'binary assets require CREDITS.md or LICENSE'}
}
if($errors.Count){$errors|%{Write-Host "::error::$_";Write-Error $_};exit 1}
Write-Host "Validated $($ids.Count) creator theme(s): manifests, all appearance properties, types, ranges, colors, assets, fonts, sounds and previews."
