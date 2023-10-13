/**
 * Mobile app for Gamepad FX Mobile script for Assetto Corsa Custom Shaders Patch. Allows to control car with a phone using its accelerometer and
 * gyroscope. Mobile phone and PC should both be connected to the same network allowing for fast and reliable data exchange.
 * 
 * Expo Go platform is used for proof-of-concept testing and because currently I personally can’t be bothered dealing with Apple Developer
 * program. Should’ve stuck with Android. Feel free to fork this thing into a proper app if you want to.
 * 
 * License: https://unlicense.org/.
 * 
 * (Easier way would be to get AC to run a simple HTTP server with a webpage accessing gyroscope data and sending it back with web sockets, but
 * webpages without HTTPS can’t access gyroscope, and webpages with HTTPS can’t access non-secure web sockets, and asking user to install a
 * custom root certificate is very unreasonable. Also, it could work better if instead of web sockets React Native implementation would use
 * a simple UDP connection, but apparently there are a lot of issues with these with iOS devices.)
 */

 import React from 'react';                                            // Basic react thing
 import { Text, View, StyleSheet, Dimensions, PanResponder, AppState,  // Some UI components, thing for monitoring touches, AppState to pause in background
   Button, TouchableHighlight, StatusBar } from 'react-native';        // …and StatusBar for fullscreen
 import { Accelerometer, Gyroscope } from 'expo-sensors';              // Accelerometer and gyroscope for steering
 import { BarCodeScanner } from 'expo-barcode-scanner';                // Bar code scanner for connecting to CSP
 import AsyncStorage from '@react-native-async-storage/async-storage'; // Storage for remembering previously used local address
 import * as Battery from 'expo-battery';                              // Battery monitoring for showring a warning icon in AC
 import * as Haptics from 'expo-haptics';                              // Haptics for simulating basic vibration
 import * as ScreenOrientation from 'expo-screen-orientation';         // Trying to force portrait orientation
 
 // Main app tweaks
 StatusBar.setBarStyle('light-content');
 ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP);
 
 // Utility functions
 function wrapRound(value) { return Math.round(Math.max(Math.min(value, 1), 0) * 999); }
 function clamp(value, min, max) { return value > min ? value < max ? value : max : min; }
 function saturate(value) { return clamp(value, 0, 1); }
 
 // Text lines
 const Lines = {
   TitleApp: 'Gamepad FX Mobile',
   TitleLayouts: 'Layout:',
   TitleScanButton: 'Scan QR code',
   MessageLoading: 'Loading',
   MessageIntroduction: 'Control your car by tilting the phone.\n\nStart Assetto Corsa with Mobile script selected in Gamepad FX settings and scan displayed QR code.',
   MessageKnownUrl: 'Trying to connect to Assetto Corsa. Rescan QR code if your network configuration has changed.',
   MessageInvalidUrl: 'This is not the valid URL. Scan the QR code displayed in Assetto Corsa.',
   MessageRequestingCameraPermission: 'Requesting for camera permission.',
   MessageCameraPermissionDenied: 'No access to camera.',
   LabelQrScan: 'Scan QR code from Assetto Corsa',
 };
 
 // Basic React styles
 const styles = StyleSheet.create({
   container: { flex: 1, justifyContent: 'center', backgroundColor: '#000', color: '#fff', position: 'relative' },    
   header: { fontSize: 22, fontWeight: '600', color: '#fff', textAlign: 'center', paddingVertical: 20 },
   textStyle: { textAlign: 'left', fontSize: 18, paddingHorizontal: 40, paddingBottom: 20, color: '#fff' },
   qrScannerMessage: { backgroundColor: 'rgba(0,0,0,0.5)', color: '#fff', width: '100%', top: '80%', left: 0, height: 40, 
     position: 'absolute', fontSize: 16, padding: 12, textAlign: 'center' },
   btnGen: { position: 'absolute', backgroundColor: '#222', borderRadius: 4 },
   btnNone: { position: 'absolute' },
   btnTouchPad: { position: 'absolute', backgroundColor: '#111', borderRadius: 4 },
   btnSmallButton: { position: 'absolute', backgroundColor: '#222', borderRadius: 4 },
   btnSystemButton: { position: 'absolute', backgroundColor: '#222', borderRadius: 8 },
   btnModifierContents: { flex: 1, justifyContent: 'center' },
   btnModifierLightPressed: { backgroundColor: '#1A1A1A' },
   btnModifierPressed: { backgroundColor: '#444' },
   btnModifierInactive: { opacity: 0.3 },
   btnContentText: { transform: [{rotate: '-90deg'}], textAlign: 'center', fontSize: '10pt', color: '#aaa' },
   btnContentGearText: { transform: [{rotate: '-90deg'}], textAlign: 'center', fontSize: '80pt', fontWeight: '100', color: '#aaa' },
   btnContentSwitch: { top: '50%', left: '75%', marginTop: -7, width: 4, height: 14, borderRadius: 3, position: 'absolute', 
     shadowRadius: 8, shadowOpacity: 1 },
   btnContentSlider: { top: 0, right: 0, height: '100%', backgroundColor: 'rgba(0,255,255,0.1)', position: 'absolute' },
   btnContentSliderSeparator: {left: '55%', top: '5%', height: '90%', width: 0, position: 'absolute',
     borderStyle: 'dotted', borderWidth: '1px', borderColor: 'rgba(255,255,255,0.1)' },
   previewRow: { flexDirection:'row', flexWrap:'wrap', justifyContent: 'center' },
   previewWrap: { borderWidth: 4, borderColor: '#000', borderRadius: 12, backgroundColor: '#000', overflow: 'hidden', marginHorizontal: 8 },
 });
 
 // Toggle button keys
 const InputKey = {
   GearUp: 'G', GearDown: 'g', HeadlightsSwitch: 'L', HeadlightsFlash: 'l', ChangingCamera: 'C', Horn: 'H',
   AbsDown: 'A', AbsUp: 'a', TcDown: 'T', TcUp: 't', TurboDown: 'U', TurboUp: 'u', WiperDown: 'W', WiperUp: 'w',
   Pause: 'E', DPadClick: 'P', DPadUp: '^', DPadRight: '>', DPadDown: '_', DPadLeft: '<', NeutralGear: '-', LowBeams: 'b', ModeSwitch: 'D',
 };
 
 // Keys used by sockets to report rare changes in state
 const StateChangeKey = {
   L: 'lights', l: 'lowbeams', A: 'absOff', T: 'tcOff', P: 'paused', D: 'needsDPad', d: 'driftMode'
 };
 
 // Parse message describing key car specs
 const ParseCarCfg = x => ({ 
   abs: !!+x[0], tc: !!+x[1], turbo: !!+x[2], clutch: !!+x[3], wipers: !!+x[4], headlights: !!+x[5], gears: +x.split(',')[1]
 });
 
 // Window size available to all (note: UI is drawn sideways, works better than to try and force iPhone into landscape orientation)
 const WindowSize = Dimensions.get('window');
 
 // Dynamic button style factories for positioning
 const StyleBase = (x, m = 0) => ({ width: x.h - m * 2, height: x.w - m * 2, top: WindowSize.height - x.x - x.w + m, left: x.y + m });
 const StyleGen = x => [ styles.btnGen, StyleBase(x, 2) ];
 const StyleNone = x => [ styles.btnNone, StyleBase(x, 0) ];
 const StyleTouchPad = x => [ styles.btnTouchPad, StyleBase(x, 2) ];
 const StyleSmallButton = x => [ styles.btnSmallButton, StyleBase(x, 2) ];
 const StyleSystemButton = x => [ styles.btnSystemButton, StyleBase(x, 8) ];
 
 // Style sheet cache
 const CachedStyleSheetFactory = () => function (k, x) { return this[k] || (this[k] = StyleSheet.create(x())); }.bind({});
 
 // Custom visual element: simple touch button changing color on contact
 const ViewTouchable = props => {
   const hit = props.mediator(props.hitKey || 'hit?');
   return <View style={hit ? [...props.style, props.stylePressed || styles.btnModifierPressed] : props.style}>{props.children}</View>; 
 }
 
 // Custom visual element: gear shift button (disables when final gear is engaged)
 const ViewGearTouchable = props => {
   const hit = props.mediator(props.hitKey || 'hit?');
   const gear = props.mediator('gear');
   return <View style={gear == props.finalGear ? [...props.style, styles.btnModifierInactive] 
     : hit ? [...props.style, props.stylePressed || styles.btnModifierPressed] : props.style}>{props.children}</View>; 
 }
 
 // Custom visual element: touch button with a small color indicator for activated state
 const vsStyles = CachedStyleSheetFactory();
 const ViewSwitch = props => {
   const hit = props.mediator(props.hitKey || 'hit?');
   return props.mediator(props.switchKey) 
     ? <View style={hit ? [...props.style, styles.btnModifierPressed] : props.style}>{props.children}
         <View style={[styles.btnContentSwitch, vsStyles(props.switchColor, () => ({backgroundColor: props.switchColor, shadowColor: props.switchColor}))]} />
       </View>
     : <View style={hit ? [...props.style, styles.btnModifierPressed] : props.style}>{props.children}</View>; 
 }
 
 // Custom visual element: touch button with color indicator for activated state alternatively changing in color (for high/low beams)
 const ViewSwitchAlt = props => {
   const hit = props.mediator(props.hitKey || 'hit?');
   const color = props.mediator(props.switchAltKey) ? props.switchAltColor : props.switchColor;
   return props.mediator(props.switchKey) 
     ? <View style={hit ? [...props.style, styles.btnModifierPressed] : props.style}>{props.children}
         <View style={[styles.btnContentSwitch, vsStyles(color, () => ({backgroundColor: color, shadowColor: color}))]} />
       </View>
     : <View style={hit ? [...props.style, styles.btnModifierPressed] : props.style}>{props.children}</View>; 
 }
 
 // Custom visual element: touch button showing its 0…1 variable value with some sort of a slider
 const ViewSlider = props => {
   const value = props.mediator(props.sliderKey);
   return value > 0 
     ? <View style={[...props.style, styles.btnModifierPressed]}>
         <View style={[styles.btnContentSlider, {left: (1 - value) * 100 + '%' }]} /><View style={styles.btnContentSliderSeparator} />{props.children}
       </View>
     : <View style={props.style}><View style={styles.btnContentSliderSeparator} />{props.children}</View>; 
 }
 
 // Custom visual element: glow outside for some sort of smooth gradient at the side of the screen
 const vsgStyles = CachedStyleSheetFactory();
 const ViewSideGlow = props => {
   const lightBar = props.mediator('lightBar');
   if (lightBar == '#000') return null;
   const elements = [];
   for (let i = 0; i < props.elementsCount; ++i) {
     elements.push(<View key={i} style={[
       vsgStyles(i, () => ({left: 0, top: (i / (props.elementsCount - 1) * (1 - props.elementWidth) * 100) + '%', width: '100%', height: (props.elementWidth * 100) + '%', position: 'absolute', backgroundColor: '#000', borderRadius: '100%', shadowRadius: props.glowRadius, shadowOpacity: props.glowOpacity})), 
       {shadowColor: lightBar}]} />);
   }
   return <View style={props.style}>{elements}</View>;
 }
 
 // Custom visual element: row of RPM LEDs
 const vrlStyles = CachedStyleSheetFactory();
 const ViewRpmLeds = props => {
   const rpmRelative = props.mediator('rpmRelative');
   const rpmFlash = props.mediator('rpmRelative:limitFlash');
   if (rpmRelative == 0) return null;
   const elements = [];
   for (let i = 0; i < props.elementsCount; ++i) {
     const color = rpmRelative == 1 ? (rpmFlash ? '#f00' : '#000')
       : rpmRelative > (props.elementsCount - i) / (props.elementsCount + 1) 
         ? i < props.elementsCount / 3 ? '#f00' : i < props.elementsCount * 2 / 3 ? '#ff0' : '#8f0' : '#000';
     const baseStyle = vrlStyles(i, () => ({left: 0, top: (i / (props.elementsCount - 1) * (1 - props.elementWidth) * 100) + '%', width: '100%', height: (props.elementWidth * 100) + '%', position: 'absolute', backgroundColor: '#000', borderRadius: '100%', shadowRadius: props.glowRadius, shadowOpacity: props.glowOpacity}));
     elements.push(<View key={i} style={color == '#000' ? baseStyle : [ baseStyle, {shadowColor: color, backgroundColor: color}]} />);
   }
   return <View style={props.style}>{elements}</View>;
 }
 
 // Custom visual element: current gear indicator
 const ViewCurrentGear = props => {
   return <View style={props.style}><Text style={styles.btnContentGearText}>{props.mediator('gear')}</Text></View>;
 }
 
 // Button-item-to-JSX-item converter
 let lastKey = 0;  // Each new JSX item should have a unique key for its state to work (items are recreated only during a layout change anyway)
 const ItemFactory = (x, mediator) => {
   const styleList = (x.style || StyleGen)(x);
   if (x.text) styleList.push(styles.btnModifierContents);
   const ItemType = x.component || ViewTouchable;
   return <ItemType key={lastKey++} style={styleList} mediator={mediator} {...x.props}>
     {typeof(x.text) === 'string' ? <Text style={styles.btnContentText}>{x.text}</Text> : null}
   </ItemType>
 };
 
 // D-Pad buttons constructor
 const ButtonsDPadFn = (x, y, w, h, o) => [
   { x: x - w / 2, y: y - h / 2 - o, w: w, h: h, text: '↑', cb: c => c.b[InputKey.DPadUp] = true },
   { x: x - w / 2, y: y - h / 2 + o, w: w, h: h, text: '↓', cb: c => c.b[InputKey.DPadDown] = true },
   { x: x - h / 2 - o, y: y - w / 2, w: h, h: w, text: '←', cb: c => c.b[InputKey.DPadLeft] = true },
   { x: x - h / 2 + o, y: y - w / 2, w: h, h: w, text: '→', cb: c => c.b[InputKey.DPadRight] = true },
   { x: x - w / 2, y: y - w / 2, w: w, h: w, text: '•', cb: c => c.b[InputKey.DPadClick] = true },
 ];
 
 // Buttons constructor
 const ButtonsFn = [
   // First layout with touchpad and messy buttons in the middle
   (w, h, displayData) => displayData.paused ? [
     // Touchpad and D-pad
     { x: w * 0.05, y: 0.1 * h, w: w * 0.4, h: h * 0.8, style: StyleTouchPad, cb: (c, x, y) => c.t.push({x: x * 0.7, y}), 
       props: { stylePressed: styles.btnModifierLightPressed } },
     ...ButtonsDPadFn(w * 0.95 - 0.5 * h, 0.5 * h, 0.3 * h, 0.3 * h, 0.3 * h),
     { x: w * 0.5, y: h * 0.85, w: w * 0.1, h: h * 0.15, style: StyleSystemButton, text: 'pause', cb: c => c.b[InputKey.Pause] = true, 
       component: ViewSwitch, props: { switchKey: 'paused', switchColor: '#fff' } },
   ] : [
     // Gas and brake pedals
     { x: 0, y: h * 0.25, w: w * 0.25, h: h * 0.75, text: 'brake', cb: (c, x, y) => c.i.brake = saturate((1 - y) * 2.2), 
       component: ViewSlider, props: { sliderKey: 'brake' } },
     { x: w * 0.75, y: h * 0.25, w: w * 0.25, h: h * 0.75, text: 'gas', cb: (c, x, y) => c.i.gas = saturate((1 - y) * 2.2), 
       component: ViewSlider, props: { sliderKey: 'gas' } },
 
     // Gear shift buttons
     { x: 0, y: 0, w: w * 0.125, h: h * 0.25, text: 'gear down', cb: c => c.b[InputKey.GearDown] = true, 
       component: ViewGearTouchable, props: { finalGear: 'R' } },
     { x: w * 0.125, y: 0, w: w * 0.125, h: h * 0.25, text: 'gear up', cb: c => c.b[InputKey.GearUp] = true, 
       component: ViewGearTouchable, props: { finalGear: displayData.carCfg.gears } },
     { x: w * 0.75, y: 0, w: w * 0.125, h: h * 0.25, text: 'gear down', cb: c => c.b[InputKey.GearDown] = true, 
       component: ViewGearTouchable, props: { finalGear: 'R' } },
     { x: w * 0.875, y: 0, w: w * 0.125, h: h * 0.25, text: 'gear up', cb: c => c.b[InputKey.GearUp] = true, 
       component: ViewGearTouchable, props: { finalGear: displayData.carCfg.gears } },
 
     // Central part (depends on if D-pad should be in focus)
     ...(displayData.needsDPad ? [
       ...ButtonsDPadFn(0.5 * w, 0.5 * h, 0.19 * h, 0.19 * h, 0.19 * h),
     ] : [
       // Touchpad and D-pad
       { x: w * 0.35, y: 0, w: w * 0.3, h: h * 0.4, style: StyleTouchPad, cb: (c, x, y) => c.t.push({x, y}), 
         props: { stylePressed: styles.btnModifierLightPressed } },
       ...ButtonsDPadFn(0.5 * w, 0.625 * h, 0.14 * h, 0.14 * h, 0.14 * h),
       
       // Wiper, neutral gear
       displayData.carCfg.wipers 
         && { x: w * 0.4 - h * 0.14 / 2, y: h * 0.41, w: h * 0.14, h: h * 0.1, style: StyleSmallButton, text: 'wipers', cb: c => c.b[InputKey.WiperUp] = true },
       displayData.carCfg.gears > 1 
         && { x: w * 0.6 - h * 0.14 / 2, y: h * 0.41, w: h * 0.14, h: h * 0.1, style: StyleSmallButton, text: 'mode', cb: c => c.b[InputKey.ModeSwitch] = true, 
       component: ViewSwitch, props: { switchKey: 'driftMode', switchColor: '#0f8' } },
     ]),
 
     // Handbrake
     { x: w * 0.25, y: h * 0.85, w: w * 0.15, h: h * 0.15, text: 'handbrake', cb: c => c.i.handbrake = 1, 
       component: ViewSwitch, props: { switchKey: 'handbrake', switchColor: '#f00' } },
     { x: w * 0.6, y: h * 0.85, w: w * 0.15, h: h * 0.15, text: 'handbrake', cb: c => c.i.handbrake = 1, 
       component: ViewSwitch, props: { switchKey: 'handbrake', switchColor: '#f00' } },
 
     // Clutch
     displayData.carCfg.clutch && { x: w * 0.25, y: 0, w: w * 0.1, h: h * 0.4, text: 'clutch', cb: c => c.i.clutch = 0 },
     displayData.carCfg.clutch && { x: w * 0.65, y: 0, w: w * 0.1, h: h * 0.4, text: 'clutch', cb: c => c.i.clutch = 0 },
 
     // Pause and camera buttons
     { x: w * 0.4, y: h * 0.85, w: w * 0.1, h: h * 0.15, style: StyleSystemButton, text: 'camera', cb: c => c.b[InputKey.ChangingCamera] = true },
     { x: w * 0.5, y: h * 0.85, w: w * 0.1, h: h * 0.15, style: StyleSystemButton, text: 'pause', cb: c => c.b[InputKey.Pause] = true, 
       component: ViewSwitch, props: { switchKey: 'paused', switchColor: '#fff' } },
 
     // Horn, headlights, ABS, TC, turbo
     { x: w * 0.64, y: h * 0.43, w: h * 0.18, h: h * 0.18, text: 'horn', cb: c => c.b[InputKey.Horn] = true },
     displayData.carCfg.headlights && { x: w * 0.62, y: h * 0.64, w: h * 0.18, h: h * 0.18, text: 'lights', cb: c => c.b[InputKey.HeadlightsSwitch] = true, 
       component: ViewSwitchAlt, props: { switchKey: 'lights', switchAltKey: 'lowbeams', switchColor: '#08f', switchAltColor: '#0f0' } },
     displayData.carCfg.abs && { x: w * 0.26, y: h * 0.42, w: h * 0.16, h: h * 0.13, text: 'abs', cb: c => c.b[InputKey.AbsUp] = true, 
       component: ViewSwitch, props: { switchKey: 'absOff', switchColor: '#f80' } },
     displayData.carCfg.tc && { x: w * 0.29, y: h * 0.56, w: h * 0.16, h: h * 0.13, text: 'tc', cb: c => c.b[InputKey.TcUp] = true, 
       component: ViewSwitch, props: { switchKey: 'tcOff', switchColor: '#f80' } },
     displayData.carCfg.turbo 
       ? { x: w * 0.31, y: h * 0.7, w: h * 0.16, h: h * 0.13, text: 'turbo', cb: c => c.b[InputKey.TurboUp] = true }
       : displayData.carCfg.headlights && { x: w * 0.31, y: h * 0.7, w: h * 0.16, h: h * 0.13, text: 'low beams', cb: c => c.b[InputKey.LowBeams] = true },
 
     // Dynamic non-touchable visual items
     { x: w * 0.2, y: h, w: w * 0.6, h: 100, component: ViewSideGlow, 
       props: { elementsCount: 5, elementWidth: 0.15, glowOpacity: 0.4, glowRadius: 30 }, style: StyleNone },
     { x: w * 0.36, y: h * 0.02, w: w * 0.28, h: h * 0.02, component: ViewRpmLeds, 
       props: { elementsCount: 15, elementWidth: h * 0.02 / (w * 0.28), glowOpacity: 1, glowRadius: 15 }, style: StyleNone },
     { x: w * 0.36, y: h * 0.05, w: w * 0.1, h: h * 0.3, component: ViewCurrentGear, style: StyleNone, text: true }
   ],
   
   // Second layout without and with a row of buttons
   (w, h, displayData) => displayData.paused ? [
     // Touchpad and D-pad
     { x: w * 0.05, y: 0.3 * h, w: w * 0.4, h: h * 0.6, style: StyleTouchPad, cb: (c, x, y) => c.t.push({x: x, y}), 
       props: { stylePressed: styles.btnModifierLightPressed } },
     ...ButtonsDPadFn(w * 0.95 - 0.5 * h, 0.5 * h, 0.3 * h, 0.3 * h, 0.3 * h),
     { x: w * 0.26, y: h * 0.03, w: w * 0.08, h: h * 0.19, style: StyleSystemButton, text: 'pause', cb: c => c.b[InputKey.Pause] = true, 
       component: ViewSwitch, props: { switchKey: 'paused', switchColor: '#fff' } },
   ] : [
     // Gas and brake pedals
     { x: 0, y: h * 0.25, w: w * 0.25, h: h * 0.75, text: 'brake', cb: (c, x, y) => c.i.brake = saturate((1 - y) * 2.2), 
       component: ViewSlider, props: { sliderKey: 'brake' } },
     { x: w * 0.75, y: h * 0.25, w: w * 0.25, h: h * 0.75, text: 'gas', cb: (c, x, y) => c.i.gas = saturate((1 - y) * 2.2), 
       component: ViewSlider, props: { sliderKey: 'gas' } },
 
     // Gear shift buttons
     { x: 0, y: 0, w: w * 0.125, h: h * 0.25, text: 'gear down', cb: c => c.b[InputKey.GearDown] = true, 
       component: ViewGearTouchable, props: { finalGear: 'R' } },
     { x: w * 0.125, y: 0, w: w * 0.125, h: h * 0.25, text: 'gear up', cb: c => c.b[InputKey.GearUp] = true, 
       component: ViewGearTouchable, props: { finalGear: displayData.carCfg.gears } },
     { x: w * 0.75, y: 0, w: w * 0.125, h: h * 0.25, text: 'gear down', cb: c => c.b[InputKey.GearDown] = true, 
       component: ViewGearTouchable, props: { finalGear: 'R' } },
     { x: w * 0.875, y: 0, w: w * 0.125, h: h * 0.25, text: 'gear up', cb: c => c.b[InputKey.GearUp] = true, 
       component: ViewGearTouchable, props: { finalGear: displayData.carCfg.gears } },
 
     // Central part
     ...ButtonsDPadFn(0.5 * w, 0.55 * h, 0.18 * h, 0.16 * h, 0.18 * h),
 
     // Clutch & handbrake
     displayData.carCfg.clutch && { x: w * 0.25, y: h * 0.25, w: w * 0.1, h: h * 0.375, text: 'clutch', cb: c => c.i.clutch = 0 },
     { x: w * 0.25, y: h * (displayData.carCfg.clutch ? 0.25 + 0.375 : 0.25), w: w * 0.1, h: h * (displayData.carCfg.clutch ? 0.375 : 0.75), 
       cb: c => c.i.handbrake = 1, props: { hitKey: 'handbrake' } },
     { x: w * 0.25, y: h * 0.85, w: w * 0.5, h: h * 0.15, text: 'handbrake', cb: c => c.i.handbrake = 1,
       component: ViewSwitch, props: { switchKey: 'handbrake', switchColor: '#f00', hitKey: 'handbrake' } },
 
     // Pause and camera buttons
     { x: w * 0.26, y: h * 0.03, w: w * 0.08, h: h * 0.19, style: StyleSystemButton, text: 'pause', cb: c => c.b[InputKey.Pause] = true, 
       component: ViewSwitch, props: { switchKey: 'paused', switchColor: '#fff' } },
     { x: w * 0.34, y: h * 0.03, w: w * 0.08, h: h * 0.19, style: StyleSystemButton, text: 'camera', cb: c => c.b[InputKey.ChangingCamera] = true },
     { x: w * 0.58, y: h * 0.03, w: w * 0.08, h: h * 0.19, style: StyleSystemButton, text: 'mode', cb: c => c.b[InputKey.ModeSwitch] = true, 
       component: ViewSwitch, props: { switchKey: 'driftMode', switchColor: '#0f8' } },
     
     // Row of extra buttons
     { x: w * 0.67, y: h * 0.04, w: h * 0.12, h: h * 0.11, text: 'horn', cb: c => c.b[InputKey.Horn] = true },
     displayData.carCfg.headlights && { x: w * 0.67, y: h * (0.04 + 0.13 * 1), w: h * 0.12, h: h * 0.11, text: 'lights', cb: c => c.b[InputKey.HeadlightsSwitch] = true, 
       component: ViewSwitchAlt, props: { switchKey: 'lights', switchAltKey: 'lowbeams', switchColor: '#08f', switchAltColor: '#0f0' } },
     displayData.carCfg.abs && { x: w * 0.67, y: h * (0.04 + 0.13 * 2), w: h * 0.12, h: h * 0.11, text: 'abs', cb: c => c.b[InputKey.AbsUp] = true, 
       component: ViewSwitch, props: { switchKey: 'absOff', switchColor: '#f80' } },
     displayData.carCfg.tc && { x: w * 0.67, y: h * (0.04 + 0.13 * 3), w: h * 0.12, h: h * 0.11, text: 'tc', cb: c => c.b[InputKey.TcUp] = true, 
       component: ViewSwitch, props: { switchKey: 'tcOff', switchColor: '#f80' } },
     displayData.carCfg.turbo 
       ? { x: w * 0.67, y: h * (0.04 + 0.13 * 4), w: h * 0.12, h: h * 0.11, text: 'turbo', cb: c => c.b[InputKey.TurboUp] = true }
       : displayData.carCfg.headlights && { x: w * 0.67, y: h * (0.04 + 0.13 * 4), w: h * 0.12, h: h * 0.11, text: 'low beams', cb: c => c.b[InputKey.LowBeams] = true },
     displayData.carCfg.wipers 
       && { x: w * 0.67, y: h * (0.04 + 0.13 * 5), w: h * 0.12, h: h * 0.11, style: StyleSmallButton, text: 'wipers', cb: c => c.b[InputKey.WiperUp] = true },
 
     // Dynamic non-touchable visual items
     { x: w * 0.2, y: h, w: w * 0.6, h: 100, component: ViewSideGlow, 
       props: { elementsCount: 5, elementWidth: 0.15, glowOpacity: 0.4, glowRadius: 30 }, style: StyleNone },
     { x: w * 0.45, y: h * 0.02, w: w * 0.1, h: h * 0.02, component: ViewRpmLeds, 
       props: { elementsCount: 15, elementWidth: h * 0.02 / (w * 0.1), glowOpacity: 1, glowRadius: 9 }, style: StyleNone },
     { x: w * 0.45, y: 0, w: w * 0.1, h: h * 0.25, component: ViewCurrentGear, style: StyleNone, text: true }
   ]
 ];
 
 // A gyroscope and accelerometer listener: takes callback and returns an object with `.enable(active)` method
 const GyroListener = listener => {
   const data = [{x: 0, y: 0, z: 0}, {x: 0, y: 0, z: 0}];
   let subs = [];
   return { enable: value => subs = !value === !subs.length ? subs : value
     ? [Accelerometer, Gyroscope].map((v, i) => (v.setUpdateInterval(1), v.addListener(a => (Object.assign(data[i], a), listener(data)))))
     : subs.filter(x => (x.remove(), false)) }
 };
 
 // Compute angle from accelerometer values
 function computeAngle(a){
   // return Math.atan2(a.y, a.x);          // Straightforward approach: uses rotation, but ignores tilts
   // return Math.asin(clamp(a.y, -1, 1));  // Smarter version: with tilts, but can’t handle device upside down
   return Math.atan2(a.y, Math.sqrt(a.x * a.x + a.z * a.z) * clamp((a.x - a.z) * 10, -1, 1)); // Strange way that should work
 }
 
 // Steer angle provider: uses smoothed accelerometer data for actual angle and gyroscope for tracking fast changes
 const SteerAngleHelper = listener => {
   let lastSteerTime = 0;  // Time from previous steer angle update
   let steerValue = 0;     // Steer angle for smoothing out accelerator-based data
   const gyroListener = GyroListener(([accel, gyro]) => {
     // Actual computation takes place only if more than 5 ms from previous data update have passed
     const curTime = Date.now();
     const dt = Math.min(curTime - lastSteerTime, 100);
     if (dt > 5) {
       lastSteerTime = curTime;
       steerValue = (steerValue * 9 + computeAngle(accel)) / 10 + (gyro.z + gyro.x) * dt / -1e3;
       listener(steerValue);
     }
   });
   return { enable: gyroListener.enable };
 };
 
 // Battery state provider
 const BatteryListener = listener => {
   const data = { charge: 0, charging: false };
   const update = arg => listener(Object.assign(data, arg || {}));
   let subs = [];
   return { enable: value => (subs = !value === !subs.length ? subs : value 
     ? (
       Battery.getBatteryLevelAsync().then(r => data.charge = r), 
       Battery.getBatteryStateAsync().then(r => data.charging = r == Battery.BatteryState.CHARGING),
       setTimeout(update, 1e3), [ 
         Battery.addBatteryLevelListener(arg => update({charge: arg.batteryLevel})),
         Battery.addBatteryStateListener(arg => update({charging: arg.batteryState == Battery.BatteryState.CHARGING}))
       ])
     : subs.filter(x => (x.remove(), false))) }
 };
 
 // A vibration helper: tries to emulate DualSense behaviour with heavy and light vibrations on the left and right sides
 const VibrationHelper = () => {
   let values = [0, 0, 0];
   let frame = 0;
   let interval;
   const fn = () => {
     if (values[2]-- < 0) return;
     if (values[1] > 0.1) Haptics.impactAsync(values[1] > 0.5 ? Haptics.ImpactFeedbackStyle.Medium : Haptics.ImpactFeedbackStyle.Light);
     if (values[0] > 0.1 && (frame = 1 - frame) == 1) Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
   };  
   return { 
     enable: value => interval = !value === (interval == null) ? interval : value ? setInterval(fn, 16) : clearInterval(interval),
     set: (left, right) => values = [left, right, 20]  
   }
 };
 
 // The main bit of logic monitoring steering, battery, receiving touch data and passing all of that to AC
 const GamepadReporter = (() => {
   let uiCallback;  // A function to pass data to UI
   let socket;      // Web socket
 
   // Counts milliseconds from a point newer than 1970
   const timeMs = function(){ return Date.now() - this }.bind(Date.now());
 
   // Send inputs from touch events
   let hadTouches = false;  // True if there were any touchpad touches in previous data frame    
   let lastInputsMsg;
   function setInputs(c) {
     // Message contains of N parts separated by “;”, first bit here is I for regular inputs: 4 numbers in 0…999 range…
     let m = `I${wrapRound(c.i.gas)},${wrapRound(c.i.brake)},${wrapRound(c.i.clutch)},${wrapRound(c.i.handbrake)},`;
     for (let k in c.b) m += k; // …and toggle button keys (one symbol per button)
 
     // If nothing changed, no need to send anything
     if (lastInputsMsg == m) m = '';
     else lastInputsMsg = m;
 
     // If there were touches reported previously or there are active touches now, add them to the message
     if (hadTouches || c.t.length > 0) {
       m += `${(m.length > 0 ? ';' : '')}T${c.t.map(x => `${wrapRound(x.x)},${wrapRound(x.y)}`).join(',')}`;
       hadTouches = c.t.length > 0;
     }
 
     // Send the message (if there is anything to send)
     if (m.length > 0) socket.send(m);
   }
   
   // Set steering angle listener
   let pingValue = 0;  // Ping value to add to steer values sent to CSP for extrapolation
   const steerListener = SteerAngleHelper(steerValue => {
     if (pingValue) {
       // Send data with adjusted ping reply packet first so that steering could be extrapolated
       socket.send(`P${pingValue + timeMs()};S${steerValue.toFixed(5)}`);
     }
   });
   
   // Set battery listener and send updates to AC
   const batteryListener = BatteryListener(args => {
     if (!socket) return; // TODO: shouldn’t happen, but for some reason occasionally does
     try {
       socket.send(`B${Math.round(args.charge * 100)},${+args.charging}`);
     } catch (e){
       console.warn(e);
     }
   });
 
   // Set vibration helper ready to receive data from AC
   const vibration = VibrationHelper();
 
   // Response to data arrived from AC
   function onMessage(msg) {
     for (let i = 0, o = 1, n; o && (n = msg.indexOf(';', i)) !== -1 || !(o = !o); i = n + 1){
       const len = (o ? n : msg.length) - i;
       if (len < 2) continue;
       const key = msg[i];
       const value = msg.substr(i + 1, len - 1);
       if (key == 'P') pingValue = +value - timeMs();
       if (key == 'V') vibration.set(...value.split(',').map(x => +x / 255));
       if (key == 'L') uiCallback('lightBar', value);
       if (key == 'R') uiCallback('rpmRelative', +value / 999);
       if (key == 'G') uiCallback('gear', value);
       if (key == 'C') uiCallback('carCfg', ParseCarCfg(value));
       if (key == 'S') uiCallback(StateChangeKey[value[0]], value[1] == '1');
     }
   }
 
   // Starts connecting if URL is correct
   function connect(url) {
     if (!uiCallback) throw new Error();
     if (socket) disconnect();
     if (!/^ws:/.test(url || '')) return false;
     uiCallback('connected', null);
     socket = new WebSocket(url);
     socket.onopen = () => {
       uiCallback('connected', true);
       steerListener.enable(true);
       batteryListener.enable(true);
       vibration.enable(true);
     };
     socket.onclose = disconnect;
     socket.onmessage = arg => onMessage(arg.data);
     return true;
   }
 
   // Disconnects everything and stop listeners
   function disconnect() {
     steerListener.enable(false);
     batteryListener.enable(false);
     vibration.enable(false);
     socket = socket && socket.close(), null;
     uiCallback('connected', false);
   }
 
   // Public API for GyroProvider
   return {
     connect: connect,
     disconnect: disconnect,
     setUICallback: c => uiCallback = c,
     setInputs: setInputs,
   };
 })();
 
 // Actual bit of UI
 export default class App extends React.Component {
   // Created here
   constructor () {
     super();
 
     // Internal state
     this.state = { 
       selectedLayout: 0,                 // Selected layout, 0…<ButtonsFn.length - 1>
       socketUrl: false,                  // False during loading stage, null on first run when there is no URL set, otherwise a string
       hasPermission: undefined,          // Undefined by default, null while requesting camera permissions, false if denied, true for QR code scanning
       mainMessage: Lines.MessageLoading  // Text message shown by regular text screen
     };
 
     // Entity for tracking all the touches
     this._panResponder = PanResponder.create({
       onStartShouldSetPanResponder: () => true,
       onMoveShouldSetPanResponder: () => true,
       onPanResponderGrant: this.onTouch.bind(this),
       onPanResponderMove: this.onTouch.bind(this),
       onPanResponderRelease: this.onTouch.bind(this),
       onPanResponderTerminate: this.onTouch.bind(this),
       onPanResponderStart: this.onTouch.bind(this),
       onPanResponderEnd: this.onTouch.bind(this),
     });
 
     // Simulation data to display (not a part of state so only components depending on actual values will be rerendered)
     this._displayData = {
       connected: false,  // True if connection is active, null if currently connecting, false if there is no connection at all
       paused: false,     // Simulation state 
       rpmRelative: 0,    // Shifting values of RPM (0 for downshift threshold, 1 for upshift threshold) 
       gear: 'N',         // Current gear: 'R', 'N' or a 1-based index
       lightBar: '#000',  // Light bar color (optionally computed by Small Tweaks module using DualSense logic)
       carCfg: {},        // Car configuration: stores data if ABS, TC, turbo, etc. is available (see `ParseCarCfg`)
       gas: 0,            // Own value: gas pedal
       brake: 0,          // Own value: brake pedal
       clutch: 1,         // Own value: clutch pedal (0 for pressed disengaging the gearbox)
       handbrake: 0       // Own value: handbrake
     };
 
     // GamepadReporter needs state callback to push updates for car state
     GamepadReporter.setUICallback(this.updateDisplayData.bind(this));
 
     // Button items and views will be stored here, reset on window dimensions change
     this.invalidateButtons();
     Dimensions.addEventListener('change', ({window}) => {
       Object.assign(WindowSize, window);
       this.invalidateButtons(true);
       this._layoutPreviews = null;
     });
   }
 
   // On mounting to UI: load previously used URL and once loaded try to apply it
   componentDidMount() {
     AsyncStorage.getItem('@socketURL')
       .then(v => this.setState({ socketUrl: v, mainMessage: v ? Lines.MessageKnownUrl : Lines.MessageIntroduction }))
       .catch(() => this.setState({ socketUrl: null, mainMessage: Lines.MessageIntroduction }));
     AsyncStorage.getItem('@selectedLayout')
       .then(v => this.setState({ selectedLayout: +v | 0 }), () => {});
     this._appStateListener = AppState.addEventListener('change', this.handleAppStateChange.bind(this));
     this._reconnectInterval = setInterval(this.tryToReconnect.bind(this), 1e3);
   }
  
   // On unmounting: disconnect reporter
   componentWillUnmount() {
     GamepadReporter.disconnect();
     clearInterval(this._rpmLimitFlashInterval);
     clearInterval(this._reconnectInterval);
     this._appStateListener && this._appStateListener.remove();
   }
 
   // If not connected, try to reconnect to last known URL from time to time
   tryToReconnect(){
     if (this._displayData.connected !== false || AppState.currentState === 'background') return;
     GamepadReporter.connect(this.state.socketUrl);
   }
 
   // If app is in background, disconnect to save battery and reduce heating
   handleAppStateChange(arg){
     if (arg === 'background') {
       GamepadReporter.disconnect();
       clearInterval(this._rpmLimitFlashInterval);
     } else {
       this.tryToReconnect();
     }
   }
 
   // Starts QR code scanning
   scanQRCode() {
     this.setState({ hasPermission: null });
     BarCodeScanner.requestPermissionsAsync().then(r => this.setState({ hasPermission: r.status === 'granted' }));
   }
 
   // QR code has been found: if fits, try to connect and store it for later
   onQRCodeScanned({data}) {
     if (GamepadReporter.connect(data)){
       this.setState({ mainMessage: Lines.MessageKnownUrl, hasPermission: undefined, socketUrl: data });
       AsyncStorage.setItem('@socketURL', data);
     } else {
       this.setState({ mainMessage: Lines.MessageInvalidUrl, hasPermission: undefined });
     }
   }
 
   // Render function creating actual UI (called on UI updates)
   render() {
     StatusBar.setHidden(this._displayData.connected);
     if (this._displayData.connected){
       return <View style={styles.container} {...this._panResponder.panHandlers}>{this.getButtonViews()}</View>;
     }
     if (this.state.hasPermission){
       return <View style={styles.container}>
         <BarCodeScanner style={StyleSheet.absoluteFillObject} onBarCodeScanned={this.onQRCodeScanned.bind(this)} />
         <Text style={styles.qrScannerMessage}>{Lines.LabelQrScan}</Text>
       </View>;
     }
     return this.state.hasPermission !== undefined
       ? this.viewText(this.state.hasPermission === false ? Lines.MessageCameraPermissionDenied : Lines.MessageRequestingCameraPermission)
       : this.viewText(this.state.mainMessage, Lines.TitleScanButton, this.state.socketUrl === false ? null : this.scanQRCode.bind(this));
   }
 
   // Simple title-and-message screens
   viewText(message, buttonTitle, clickCallback) {
     return <View style={styles.container}>
       <Text style={styles.header}>{Lines.TitleApp}</Text>
       <Text style={styles.textStyle}>{message}</Text>
       { clickCallback ? <Button title={buttonTitle} onPress={clickCallback} /> : null }
       { clickCallback ? this.viewLayoutSelector() : null }
     </View>;
   }
   
   // Couple of things for layout selection
   viewLayoutSelector() {
     return <>
       <Text style={[styles.header, { marginTop: 80 }]}>{Lines.TitleLayouts}</Text>
       <View style={styles.previewRow}>
       {this.layoutPreviews().map((x, i) => <TouchableHighlight onPress={() => (AsyncStorage.setItem('@selectedLayout', `${i}`), this.invalidateButtons({ selectedLayout: i }))} 
         style={[ styles.previewWrap, {width: WindowSize.height * 0.15 + 8, height: WindowSize.width * 0.15 + 8, borderColor: this.state.selectedLayout == i ? '#08f' : '#000' }]} >
         <View style={{ transform: [{translateX: WindowSize.height * 0.075}, {translateY: 10}, {rotate: '90deg'}, {scale: 0.15}] }}>{x}</View>
       </TouchableHighlight>)}
       </View>
     </>;
   }
 
   // Generates layout preview elements
   layoutPreviews(){
     return this._layoutPreviews || (this._layoutPreviews = ButtonsFn.map(x => {
       const ddp = { gear: 2, lightBar: '#ff0', rpmRelative: 0.7, carCfg: { gears: 5, abs: true, tc: true, turbo: true, clutch: true, wipers: true, headlights: true } };
       return x(WindowSize.height, WindowSize.width, ddp).filter(x => x).map(x => ItemFactory(x, k => ddp[k]));
     }));
   }
 
   // Drops cached button items to be remade next time they are needed
   invalidateButtons(stateUpdate) {
     this._buttonItems = this._buttonViews = null;
     if (stateUpdate) this.setState(typeof(stateUpdate) === 'boolean' ? {} : stateUpdate);
   }
 
   // Sets default display data listeners
   setupBaseMediators() {
     return {
       rpmRelative: [value => {  // If relative RPM is at 100%, set interval for flashing indicators
         if (value == 1) {
           this._rpmLimitFlashInterval = setInterval(() => this.updateDisplayData('rpmRelative:limitFlash', this._flashStage = !this._flashStage), 200);
           this.updateDisplayData('rpmRelative:limitFlash', this._flashStage = true);
         } else if (this._rpmLimitFlashInterval != null) {
           this._rpmLimitFlashInterval = clearInterval(this._rpmLimitFlashInterval);
         }
       }]
     };
   }
 
   // Updates display data value and invoke listener callbacks if any
   updateDisplayData(key, value) {
     if (value !== this._displayData[key]) {
       this._displayData[key] = value;
       if (key === 'carCfg'      // Invalidate buttons on car configuration change (some cars don’t need some buttons)
         || key === 'paused'     // Invalidate buttons when paused: only D-pad and touchpad are needed there
         || key === 'needsDPad'  // Invalidate buttons when D-pad is needed: show it instead of touchpad
         || key === 'connected'){
         if (key === 'connected') console.log('Connected state update', value);
         this.invalidateButtons(true);
       } else if (this._buttonMediators && this._buttonMediators[key]) {
         for (let i of this._buttonMediators[key]) i(value);
       }
     }
   }
 
   // Returns list of button items (creating on first call or if invalidated due to window resize)
   getButtons() {
     return this._buttonItems || (this._buttonItems = ButtonsFn[this.state.selectedLayout](WindowSize.height, WindowSize.width, this._displayData).filter(x => x));
   }
 
   // Returns list of views for button items (creating on first call or if invalidated due to visual state change)
   getButtonViews() {
     return this._buttonViews || (() => {
       const mediatorSetter = function (k) { return this[k] || (this[k] = []) }.bind(this._buttonMediators = this.setupBaseMediators());
       return this._buttonViews = this.getButtons().map((item, index) => ItemFactory(item, key => {
         let addListener = false;
         const v = React.useState(() => ((addListener = true), this._displayData[key.replace('?', index)]));
         if (addListener) mediatorSetter(key.replace('?', index)).push(v[1]);
         return v[0];
       }));
     })();
   }
 
   // React to any touches
   onTouch(evt) {
     if (!this._displayData.connected) return;
 
     // Context: analog inputs, table of pressed buttons, array of touchpad events
     const ctx = {i: { gas: 0, brake: 0, clutch: 1, handbrake: 0 }, b: {}, t: []};
 
     // Iterate over buttons and compare them with touches
     const btns = this.getButtons();
     for (let j = 0; j < btns.length; ++j) {
       const i = btns[j];
       if (!i.cb) continue;
       let anyHit = false;
       for (let p of evt.nativeEvent.touches) {
         const x = (WindowSize.height - p.pageY - i.x) / i.w;
         const y = (p.pageX - i.y) / i.h;
         if (x > 0 && y > 0 && x < 1 && y < 1) {
           i.cb(ctx, x, y);
           anyHit = true;
         }
       }
       if (i.hit !== anyHit) {
         i.hit = anyHit;
         this.updateDisplayData(`hit${j}`, anyHit);
       }
     }
 
     // Send data to AC
     GamepadReporter.setInputs(ctx);
 
     // Invoke listeners for analog data: some controls might need it
     this.updateDisplayData('gas', ctx.i.gas);
     this.updateDisplayData('brake', ctx.i.brake);
     this.updateDisplayData('handbrake', ctx.i.handbrake);
     this.updateDisplayData('clutch', ctx.i.clutch);
   }
 }
 
 