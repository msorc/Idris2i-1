module Hints

-- 200 implementations of one interface, and 20 functions with 10 arguments
-- that resolve the interface 60 times each: every search has 200
-- implementations and 10 local variables as candidates, of which one
-- matches. The others clash with the goal (`Tag T3` against `Tag T7`, or a
-- local of type `T7` against `Tag T3`) and are rejected without unifying
-- them with it: when each was unified with the goal, the searches took six
-- times as long, and the whole file twice as long.

interface Tag a where
  tag : a -> Nat

data T0 = MkT0

Tag T0 where
  tag _ = 0

data T1 = MkT1

Tag T1 where
  tag _ = 1

data T2 = MkT2

Tag T2 where
  tag _ = 2

data T3 = MkT3

Tag T3 where
  tag _ = 3

data T4 = MkT4

Tag T4 where
  tag _ = 4

data T5 = MkT5

Tag T5 where
  tag _ = 5

data T6 = MkT6

Tag T6 where
  tag _ = 6

data T7 = MkT7

Tag T7 where
  tag _ = 7

data T8 = MkT8

Tag T8 where
  tag _ = 8

data T9 = MkT9

Tag T9 where
  tag _ = 9

data T10 = MkT10

Tag T10 where
  tag _ = 10

data T11 = MkT11

Tag T11 where
  tag _ = 11

data T12 = MkT12

Tag T12 where
  tag _ = 12

data T13 = MkT13

Tag T13 where
  tag _ = 13

data T14 = MkT14

Tag T14 where
  tag _ = 14

data T15 = MkT15

Tag T15 where
  tag _ = 15

data T16 = MkT16

Tag T16 where
  tag _ = 16

data T17 = MkT17

Tag T17 where
  tag _ = 17

data T18 = MkT18

Tag T18 where
  tag _ = 18

data T19 = MkT19

Tag T19 where
  tag _ = 19

data T20 = MkT20

Tag T20 where
  tag _ = 20

data T21 = MkT21

Tag T21 where
  tag _ = 21

data T22 = MkT22

Tag T22 where
  tag _ = 22

data T23 = MkT23

Tag T23 where
  tag _ = 23

data T24 = MkT24

Tag T24 where
  tag _ = 24

data T25 = MkT25

Tag T25 where
  tag _ = 25

data T26 = MkT26

Tag T26 where
  tag _ = 26

data T27 = MkT27

Tag T27 where
  tag _ = 27

data T28 = MkT28

Tag T28 where
  tag _ = 28

data T29 = MkT29

Tag T29 where
  tag _ = 29

data T30 = MkT30

Tag T30 where
  tag _ = 30

data T31 = MkT31

Tag T31 where
  tag _ = 31

data T32 = MkT32

Tag T32 where
  tag _ = 32

data T33 = MkT33

Tag T33 where
  tag _ = 33

data T34 = MkT34

Tag T34 where
  tag _ = 34

data T35 = MkT35

Tag T35 where
  tag _ = 35

data T36 = MkT36

Tag T36 where
  tag _ = 36

data T37 = MkT37

Tag T37 where
  tag _ = 37

data T38 = MkT38

Tag T38 where
  tag _ = 38

data T39 = MkT39

Tag T39 where
  tag _ = 39

data T40 = MkT40

Tag T40 where
  tag _ = 40

data T41 = MkT41

Tag T41 where
  tag _ = 41

data T42 = MkT42

Tag T42 where
  tag _ = 42

data T43 = MkT43

Tag T43 where
  tag _ = 43

data T44 = MkT44

Tag T44 where
  tag _ = 44

data T45 = MkT45

Tag T45 where
  tag _ = 45

data T46 = MkT46

Tag T46 where
  tag _ = 46

data T47 = MkT47

Tag T47 where
  tag _ = 47

data T48 = MkT48

Tag T48 where
  tag _ = 48

data T49 = MkT49

Tag T49 where
  tag _ = 49

data T50 = MkT50

Tag T50 where
  tag _ = 50

data T51 = MkT51

Tag T51 where
  tag _ = 51

data T52 = MkT52

Tag T52 where
  tag _ = 52

data T53 = MkT53

Tag T53 where
  tag _ = 53

data T54 = MkT54

Tag T54 where
  tag _ = 54

data T55 = MkT55

Tag T55 where
  tag _ = 55

data T56 = MkT56

Tag T56 where
  tag _ = 56

data T57 = MkT57

Tag T57 where
  tag _ = 57

data T58 = MkT58

Tag T58 where
  tag _ = 58

data T59 = MkT59

Tag T59 where
  tag _ = 59

data T60 = MkT60

Tag T60 where
  tag _ = 60

data T61 = MkT61

Tag T61 where
  tag _ = 61

data T62 = MkT62

Tag T62 where
  tag _ = 62

data T63 = MkT63

Tag T63 where
  tag _ = 63

data T64 = MkT64

Tag T64 where
  tag _ = 64

data T65 = MkT65

Tag T65 where
  tag _ = 65

data T66 = MkT66

Tag T66 where
  tag _ = 66

data T67 = MkT67

Tag T67 where
  tag _ = 67

data T68 = MkT68

Tag T68 where
  tag _ = 68

data T69 = MkT69

Tag T69 where
  tag _ = 69

data T70 = MkT70

Tag T70 where
  tag _ = 70

data T71 = MkT71

Tag T71 where
  tag _ = 71

data T72 = MkT72

Tag T72 where
  tag _ = 72

data T73 = MkT73

Tag T73 where
  tag _ = 73

data T74 = MkT74

Tag T74 where
  tag _ = 74

data T75 = MkT75

Tag T75 where
  tag _ = 75

data T76 = MkT76

Tag T76 where
  tag _ = 76

data T77 = MkT77

Tag T77 where
  tag _ = 77

data T78 = MkT78

Tag T78 where
  tag _ = 78

data T79 = MkT79

Tag T79 where
  tag _ = 79

data T80 = MkT80

Tag T80 where
  tag _ = 80

data T81 = MkT81

Tag T81 where
  tag _ = 81

data T82 = MkT82

Tag T82 where
  tag _ = 82

data T83 = MkT83

Tag T83 where
  tag _ = 83

data T84 = MkT84

Tag T84 where
  tag _ = 84

data T85 = MkT85

Tag T85 where
  tag _ = 85

data T86 = MkT86

Tag T86 where
  tag _ = 86

data T87 = MkT87

Tag T87 where
  tag _ = 87

data T88 = MkT88

Tag T88 where
  tag _ = 88

data T89 = MkT89

Tag T89 where
  tag _ = 89

data T90 = MkT90

Tag T90 where
  tag _ = 90

data T91 = MkT91

Tag T91 where
  tag _ = 91

data T92 = MkT92

Tag T92 where
  tag _ = 92

data T93 = MkT93

Tag T93 where
  tag _ = 93

data T94 = MkT94

Tag T94 where
  tag _ = 94

data T95 = MkT95

Tag T95 where
  tag _ = 95

data T96 = MkT96

Tag T96 where
  tag _ = 96

data T97 = MkT97

Tag T97 where
  tag _ = 97

data T98 = MkT98

Tag T98 where
  tag _ = 98

data T99 = MkT99

Tag T99 where
  tag _ = 99

data T100 = MkT100

Tag T100 where
  tag _ = 100

data T101 = MkT101

Tag T101 where
  tag _ = 101

data T102 = MkT102

Tag T102 where
  tag _ = 102

data T103 = MkT103

Tag T103 where
  tag _ = 103

data T104 = MkT104

Tag T104 where
  tag _ = 104

data T105 = MkT105

Tag T105 where
  tag _ = 105

data T106 = MkT106

Tag T106 where
  tag _ = 106

data T107 = MkT107

Tag T107 where
  tag _ = 107

data T108 = MkT108

Tag T108 where
  tag _ = 108

data T109 = MkT109

Tag T109 where
  tag _ = 109

data T110 = MkT110

Tag T110 where
  tag _ = 110

data T111 = MkT111

Tag T111 where
  tag _ = 111

data T112 = MkT112

Tag T112 where
  tag _ = 112

data T113 = MkT113

Tag T113 where
  tag _ = 113

data T114 = MkT114

Tag T114 where
  tag _ = 114

data T115 = MkT115

Tag T115 where
  tag _ = 115

data T116 = MkT116

Tag T116 where
  tag _ = 116

data T117 = MkT117

Tag T117 where
  tag _ = 117

data T118 = MkT118

Tag T118 where
  tag _ = 118

data T119 = MkT119

Tag T119 where
  tag _ = 119

data T120 = MkT120

Tag T120 where
  tag _ = 120

data T121 = MkT121

Tag T121 where
  tag _ = 121

data T122 = MkT122

Tag T122 where
  tag _ = 122

data T123 = MkT123

Tag T123 where
  tag _ = 123

data T124 = MkT124

Tag T124 where
  tag _ = 124

data T125 = MkT125

Tag T125 where
  tag _ = 125

data T126 = MkT126

Tag T126 where
  tag _ = 126

data T127 = MkT127

Tag T127 where
  tag _ = 127

data T128 = MkT128

Tag T128 where
  tag _ = 128

data T129 = MkT129

Tag T129 where
  tag _ = 129

data T130 = MkT130

Tag T130 where
  tag _ = 130

data T131 = MkT131

Tag T131 where
  tag _ = 131

data T132 = MkT132

Tag T132 where
  tag _ = 132

data T133 = MkT133

Tag T133 where
  tag _ = 133

data T134 = MkT134

Tag T134 where
  tag _ = 134

data T135 = MkT135

Tag T135 where
  tag _ = 135

data T136 = MkT136

Tag T136 where
  tag _ = 136

data T137 = MkT137

Tag T137 where
  tag _ = 137

data T138 = MkT138

Tag T138 where
  tag _ = 138

data T139 = MkT139

Tag T139 where
  tag _ = 139

data T140 = MkT140

Tag T140 where
  tag _ = 140

data T141 = MkT141

Tag T141 where
  tag _ = 141

data T142 = MkT142

Tag T142 where
  tag _ = 142

data T143 = MkT143

Tag T143 where
  tag _ = 143

data T144 = MkT144

Tag T144 where
  tag _ = 144

data T145 = MkT145

Tag T145 where
  tag _ = 145

data T146 = MkT146

Tag T146 where
  tag _ = 146

data T147 = MkT147

Tag T147 where
  tag _ = 147

data T148 = MkT148

Tag T148 where
  tag _ = 148

data T149 = MkT149

Tag T149 where
  tag _ = 149

data T150 = MkT150

Tag T150 where
  tag _ = 150

data T151 = MkT151

Tag T151 where
  tag _ = 151

data T152 = MkT152

Tag T152 where
  tag _ = 152

data T153 = MkT153

Tag T153 where
  tag _ = 153

data T154 = MkT154

Tag T154 where
  tag _ = 154

data T155 = MkT155

Tag T155 where
  tag _ = 155

data T156 = MkT156

Tag T156 where
  tag _ = 156

data T157 = MkT157

Tag T157 where
  tag _ = 157

data T158 = MkT158

Tag T158 where
  tag _ = 158

data T159 = MkT159

Tag T159 where
  tag _ = 159

data T160 = MkT160

Tag T160 where
  tag _ = 160

data T161 = MkT161

Tag T161 where
  tag _ = 161

data T162 = MkT162

Tag T162 where
  tag _ = 162

data T163 = MkT163

Tag T163 where
  tag _ = 163

data T164 = MkT164

Tag T164 where
  tag _ = 164

data T165 = MkT165

Tag T165 where
  tag _ = 165

data T166 = MkT166

Tag T166 where
  tag _ = 166

data T167 = MkT167

Tag T167 where
  tag _ = 167

data T168 = MkT168

Tag T168 where
  tag _ = 168

data T169 = MkT169

Tag T169 where
  tag _ = 169

data T170 = MkT170

Tag T170 where
  tag _ = 170

data T171 = MkT171

Tag T171 where
  tag _ = 171

data T172 = MkT172

Tag T172 where
  tag _ = 172

data T173 = MkT173

Tag T173 where
  tag _ = 173

data T174 = MkT174

Tag T174 where
  tag _ = 174

data T175 = MkT175

Tag T175 where
  tag _ = 175

data T176 = MkT176

Tag T176 where
  tag _ = 176

data T177 = MkT177

Tag T177 where
  tag _ = 177

data T178 = MkT178

Tag T178 where
  tag _ = 178

data T179 = MkT179

Tag T179 where
  tag _ = 179

data T180 = MkT180

Tag T180 where
  tag _ = 180

data T181 = MkT181

Tag T181 where
  tag _ = 181

data T182 = MkT182

Tag T182 where
  tag _ = 182

data T183 = MkT183

Tag T183 where
  tag _ = 183

data T184 = MkT184

Tag T184 where
  tag _ = 184

data T185 = MkT185

Tag T185 where
  tag _ = 185

data T186 = MkT186

Tag T186 where
  tag _ = 186

data T187 = MkT187

Tag T187 where
  tag _ = 187

data T188 = MkT188

Tag T188 where
  tag _ = 188

data T189 = MkT189

Tag T189 where
  tag _ = 189

data T190 = MkT190

Tag T190 where
  tag _ = 190

data T191 = MkT191

Tag T191 where
  tag _ = 191

data T192 = MkT192

Tag T192 where
  tag _ = 192

data T193 = MkT193

Tag T193 where
  tag _ = 193

data T194 = MkT194

Tag T194 where
  tag _ = 194

data T195 = MkT195

Tag T195 where
  tag _ = 195

data T196 = MkT196

Tag T196 where
  tag _ = 196

data T197 = MkT197

Tag T197 where
  tag _ = 197

data T198 = MkT198

Tag T198 where
  tag _ = 198

data T199 = MkT199

Tag T199 where
  tag _ = 199

use0 : T0 -> T13 -> T26 -> T39 -> T52 -> T65 -> T78 -> T91 -> T104 -> T117 -> List Nat
use0 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use1 : T7 -> T20 -> T33 -> T46 -> T59 -> T72 -> T85 -> T98 -> T111 -> T124 -> List Nat
use1 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use2 : T14 -> T27 -> T40 -> T53 -> T66 -> T79 -> T92 -> T105 -> T118 -> T131 -> List Nat
use2 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use3 : T21 -> T34 -> T47 -> T60 -> T73 -> T86 -> T99 -> T112 -> T125 -> T138 -> List Nat
use3 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use4 : T28 -> T41 -> T54 -> T67 -> T80 -> T93 -> T106 -> T119 -> T132 -> T145 -> List Nat
use4 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use5 : T35 -> T48 -> T61 -> T74 -> T87 -> T100 -> T113 -> T126 -> T139 -> T152 -> List Nat
use5 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use6 : T42 -> T55 -> T68 -> T81 -> T94 -> T107 -> T120 -> T133 -> T146 -> T159 -> List Nat
use6 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use7 : T49 -> T62 -> T75 -> T88 -> T101 -> T114 -> T127 -> T140 -> T153 -> T166 -> List Nat
use7 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use8 : T56 -> T69 -> T82 -> T95 -> T108 -> T121 -> T134 -> T147 -> T160 -> T173 -> List Nat
use8 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use9 : T63 -> T76 -> T89 -> T102 -> T115 -> T128 -> T141 -> T154 -> T167 -> T180 -> List Nat
use9 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use10 : T70 -> T83 -> T96 -> T109 -> T122 -> T135 -> T148 -> T161 -> T174 -> T187 -> List Nat
use10 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use11 : T77 -> T90 -> T103 -> T116 -> T129 -> T142 -> T155 -> T168 -> T181 -> T194 -> List Nat
use11 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use12 : T84 -> T97 -> T110 -> T123 -> T136 -> T149 -> T162 -> T175 -> T188 -> T1 -> List Nat
use12 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use13 : T91 -> T104 -> T117 -> T130 -> T143 -> T156 -> T169 -> T182 -> T195 -> T8 -> List Nat
use13 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use14 : T98 -> T111 -> T124 -> T137 -> T150 -> T163 -> T176 -> T189 -> T2 -> T15 -> List Nat
use14 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use15 : T105 -> T118 -> T131 -> T144 -> T157 -> T170 -> T183 -> T196 -> T9 -> T22 -> List Nat
use15 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use16 : T112 -> T125 -> T138 -> T151 -> T164 -> T177 -> T190 -> T3 -> T16 -> T29 -> List Nat
use16 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use17 : T119 -> T132 -> T145 -> T158 -> T171 -> T184 -> T197 -> T10 -> T23 -> T36 -> List Nat
use17 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use18 : T126 -> T139 -> T152 -> T165 -> T178 -> T191 -> T4 -> T17 -> T30 -> T43 -> List Nat
use18 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

use19 : T133 -> T146 -> T159 -> T172 -> T185 -> T198 -> T11 -> T24 -> T37 -> T50 -> List Nat
use19 x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = [tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9, tag x0, tag x1, tag x2, tag x3, tag x4, tag x5, tag x6, tag x7, tag x8, tag x9]

