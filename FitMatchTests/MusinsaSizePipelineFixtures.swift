import Foundation

enum MusinsaSizePipelineFixtures {
    static let product6391245Grid = [
        ["사이즈(cm)", "총기장", "어깨너비", "가슴둘레"],
        ["XS", "49", "30", "90"],
        ["S", "51", "32", "95"],
        ["M", "53", "34", "100"]
    ]

    static let product6219777HTML = """
    <table>
      <tr><th>치수항목</th><th>093(S)</th><th>095(M)</th><th>100(L)</th><th>105(XL)</th><th>110(XXL)</th></tr>
      <tr><th>가슴둘레</th><td>110</td><td>115</td><td>120</td><td>125</td><td>130</td></tr>
      <tr><th>총길이</th><td>65</td><td>67</td><td>69</td><td>71</td><td>73</td></tr>
    </table><p>단위: cm</p>
    """

    static let product6045676HTML = """
    <table>
      <tr><th>사이즈</th><th>가슴둘레</th><th>밑단둘레</th><th>총길이</th><th>화장</th></tr>
      <tr><td>85 / XS</td><td>113</td><td>103</td><td>57</td><td>46</td></tr>
      <tr><td>90 / S</td><td>122</td><td>108</td><td>66</td><td>51</td></tr>
      <tr><td>95 / M</td><td>127</td><td>113</td><td>68</td><td>52.5</td></tr>
      <tr><td>100 / L</td><td>132</td><td>118</td><td>70</td><td>54</td></tr>
      <tr><td>105 / XL</td><td>137</td><td>123</td><td>72</td><td>55.5</td></tr>
      <tr><td>110 / 2XL</td><td>142</td><td>128</td><td>74</td><td>57</td></tr>
      <tr><td>115 / 3XL</td><td>147</td><td>133</td><td>74</td><td>57</td></tr>
    </table><p>단위: cm</p>
    """

    static let product6692774Grid = [
        ["치수항목", "65 (S)", "70 (WM)"],
        ["허리둘레", "73.5 cm", "780mm"],
        ["허벅지둘레", "58CM", "620mm"],
        ["밑위길이", "27", "28"],
        ["밑단둘레", "44cm", "460mm"]
    ]

    static let bodyRecommendationHTML = """
    <h2>신체 권장 치수</h2>
    <table>
      <tr><th>사이즈</th><th>가슴둘레</th><th>총장</th></tr>
      <tr><td>S</td><td>90</td><td>165</td></tr>
      <tr><td>M</td><td>95</td><td>170</td></tr>
    </table>
    """

    static let productNoticeHTML = """
    <table>
      <tr><th>품명</th><th>치수</th></tr>
      <tr><td>의류</td><td>상세페이지 참조</td></tr>
    </table>
    """

    static let singleShoeReferenceGrid = [
        ["항목", "값"],
        ["발길이", "235mm"],
        ["굽높이", "4cm"]
    ]
}
