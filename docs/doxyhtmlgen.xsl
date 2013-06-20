<?xml version="1.0" encoding="UTF-8"?>

<!--
 Copyright (C) 2013 Intel Corporation
 
 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; either version 2
 of the License, or (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

 Author: Mohit Gambhir (mohit.gambhir@intel.com)
 -->

<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
<xsl:output method="xml" indent="yes"/>
<xsl:param name="project" select="'leap-docs'"/>
  <xsl:template name="head">
    <meta http-equiv="Content-Type" content="text/xhtml;charset=UTF-8"/>
    <meta http-equiv="X-UA-Compatible" content="IE=9"/>
    <script type="text/javascript" src="jquery.js"/>
    <script type="text/javascript">$(document).ready(initResizable);
    $(window).load(resizeHeight);</script>
    <link href="search/search.css" rel="stylesheet" type="text/css"/>
    <script type="text/javascript" src="search/search.js"/>
    <script type="text/javascript">$(document).ready(function() {
                if ($('.searchresults').length &gt; 0) { searchBox.DOMSearchField().focus(); }
                        });</script>
    <link rel="search" href="search-opensearch.php?v=opensearch.xml" type="application/opensearchdescription+xml" title="LEAP"/>
    <link href="stylesheet.css" rel="stylesheet" type="text/css"/>
  </xsl:template>
  <xsl:template name="body-header">
    <div id="top">
      <div id="titlearea">
        <table cellspacing="0" cellpadding="0">
          <tbody>
            <tr style="height: 56px;">
              <td style="padding-left: 0.5em;">
                <div id="projectname">
                  <a href="index.html">
                    <img id="title" src="title.png"/>
                  </a>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <!-- end header part -->
      <script type="text/javascript">var searchBox = new SearchBox("searchBox", "search",false,'Search');</script>
      <div id="MSearchBox" class="MSearchBoxInactive">
        <div class="left">
          <form id="FSeaerchBox" action="search.html" method="get">
            <img id="MSearchSelect" src="search/mag.png" alt=""/>
            <input type="text" id="MSearchField" name="query" value="Search" size="20" accesskey="S" onfocus="searchBox.OnSearchFieldFocus(true)" onblur="searchBox.OnSearchFieldFocus(false)"/>
          </form>
        </div>
        <div class="right"/>
      </div>
    </div>
    <!-- top -->
  </xsl:template>
  <xsl:template match="/doxygenindex">
    <html>
      <head>
        <title><xsl:value-of select="$project"/>: Main Page</title>
        <xsl:call-template name="head"/>
      </head>
      <body>
        <xsl:call-template name="body-header"/>
        <div class="doc-content">
          <div class="header">
            <div class="headertitle">
              <div class="title">Leap Repositrories</div>
            </div>
          </div>
          <!--header-->
          <div class="contents">
            <div class="directory">
              <table class="directory">
                <xsl:for-each select="compound[@kind='group']">
                  <xsl:variable name="group" select="name"/>
                  <xsl:if test="count(document(concat('dox/xml/group__',normalize-space($group),'.xml'))//innergroup) &gt; 0">
                  <tr>
                    <td>
                      <xsl:element name="a">
                        <xsl:attribute name="href">
                          <xsl:value-of select="concat('group__', normalize-space($group), '.html')"/>
                        </xsl:attribute>
                        <xsl:value-of select="document(concat('dox/xml/group__',normalize-space($group),'.xml'))//compounddef/title"/>
                      </xsl:element>
                    </td>
                  </tr>
                </xsl:if>
                </xsl:for-each>
              </table>
            </div>
            <!-- directory -->
          </div>
          <!-- contents -->
        </div>
        <!-- doc-contents -->
      </body>
    </html>
  </xsl:template>
  <!-- To extract list of Subgroups or Interfaces/Modules/Functions -->
  <xsl:template match="/doxygen/compounddef[@kind='group']">
    <html>
      <head>
        <title>
          <xsl:value-of select="$project"/>:
          <xsl:value-of select="//title"/>
        </title>
        <xsl:call-template name="head"/>
      </head>
      <body>
        <xsl:call-template name="body-header"/>
        <div class="doc-contents">
          <div class="header">
            <div class="headertitle">
              <div class="title">
                <xsl:value-of select="//title"/>
              </div>
            </div>
          </div>
          <!--header-->
          <div class="contents">
            <xsl:choose>
            <xsl:when test="count(innergroup) = 0">
            <div class="textblock">
              List of
              <xsl:value-of select="//title"/>
              . Click on any to view details
            </div>

            <table class="memberdecls">
              <xsl:for-each select="innerclass">
                <tr class="memitem:">
                  <td class="memItemRight" valign="bottom">
                    <!--#Create an html reference from the construct name  -->
                    <xsl:element name="a">
                      <xsl:attribute name="href">
                        <xsl:variable name="constructName" select="@refid"/>
                        <xsl:value-of select="concat($constructName,'.html')"/>
                      </xsl:attribute>
                      <xsl:call-template name="string-replace-less-than">
                        <xsl:with-param name="text">
                          <xsl:call-template name="string-replace-greater-than">
                            <xsl:with-param name="text" select="."/>
                          </xsl:call-template>
                        </xsl:with-param>
                      </xsl:call-template>
                    </xsl:element>
                  </td>
                </tr>
              </xsl:for-each>
            </table>
            </xsl:when>
            <xsl:otherwise>
            <div class="textblock">
              List of Bluespec Constructs in 
              <xsl:value-of select="//title"/>
              . Click on any to view details
            </div>
            <table class="memberdecls">
              <xsl:for-each select="innergroup">
                <tr class="memitem:">
                  <td class="memItemRight" valign="bottom">
                    <!--#Create an html reference from the construct name  -->
                    <xsl:element name="a">
                      <xsl:attribute name="href">
                        <xsl:variable name="constructName" select="@refid"/>
                        <xsl:value-of select="concat($constructName,'.html')"/>
                      </xsl:attribute>
                      <xsl:call-template name="string-replace-less-than">
                        <xsl:with-param name="text">
                          <xsl:call-template name="string-replace-greater-than">
                            <xsl:with-param name="text" select="."/>
                          </xsl:call-template>
                        </xsl:with-param>
                      </xsl:call-template>
                    </xsl:element>
                  </td>
                </tr>
              </xsl:for-each>
              </table>
            </xsl:otherwise>
            </xsl:choose>
          </div>
          <!-- contents -->
        </div>
        <!-- doc-contents -->
      </body>
    </html>
  </xsl:template>
  <!-- Extract class definitions> -->
  <xsl:template match="/doxygen/compounddef[@kind='class']">
    <html>
      <head>
        <title>
          <xsl:value-of select="$project"/>:
          <xsl:call-template name="string-replace-less-than">
            <xsl:with-param name="text">
              <xsl:call-template name="string-replace-greater-than">
                <xsl:with-param name="text" select="compoundname"/>
              </xsl:call-template>
            </xsl:with-param>
          </xsl:call-template>
        </title>
        <xsl:call-template name="head"/>
      </head>
      <body>
        <xsl:call-template name="body-header"/>
        <div class="doc-contents">
          <div class="header">
            <div class="headertitle">
              <div class="title">
                <xsl:call-template name="string-replace-less-than">
                  <xsl:with-param name="text">
                    <xsl:call-template name="string-replace-greater-than">
                      <xsl:with-param name="text" select="compoundname"/>
                    </xsl:call-template>
                  </xsl:with-param>
                </xsl:call-template>
              </div>
            </div>
          </div>
          <!--header-->
          <div class="contents">
            <xsl:variable name="sourcefile">
              <xsl:call-template name="getfilename">
                <xsl:with-param name="path" select="location/@file"/>
              </xsl:call-template>
            </xsl:variable>
            <xsl:variable name="xmlsourcefile" select="concat(document('dox/xml/index.xml')/doxygenindex/compound[name=$sourcefile]/@refid,'.xml')"/>
            <xsl:variable name="htmlsourcefile" select="document(concat('dox/xml/',$xmlsourcefile))/doxygen/compounddef/detaileddescription/para/ulink"/>
            <xsl:variable name="lno" select="location/@line"/>
            <div class="textblock">
              <p>
                <xsl:value-of select="detaileddescription/para"/>
              </p>
              <p>
                Definition at line
                <a class="el">
                  <xsl:attribute name="href">
                    <xsl:value-of select="concat($htmlsourcefile, '#L', $lno)"/>
                  </xsl:attribute>
                  <xsl:value-of select="$lno"/>
                </a>
                of file
                <a class="el">
                  <xsl:attribute name="href">
                    <xsl:value-of select="$htmlsourcefile"/>
                  </xsl:attribute>
                  <xsl:value-of select="$sourcefile"/>
                </a>
              </p>
            </div>
            <xsl:if test="count(derivedcompoundref) &gt; 0">
            <table class="memberdecls">
                <tr class="heading">
                  <td colspan="1">
                    <h2 class="groupheader">
                      Modules implementing the Interface
                    </h2>
                  </td>
                </tr>
                <xsl:for-each select = "derivedcompoundref">
                  <tr class="memitem:">
                    <td class="memItemRight" valign="bottom">
                    <xsl:element name="a">
                      <xsl:attribute name="href">
                        <xsl:variable name="constructName" select="@refid"/>
                        <xsl:value-of select="concat($constructName,'.html')"/>
                      </xsl:attribute>
                      <xsl:call-template name="string-replace-less-than">
                        <xsl:with-param name="text">
                          <xsl:call-template name="string-replace-greater-than">
                            <xsl:with-param name="text" select="."/>
                           </xsl:call-template>
                         </xsl:with-param>
                       </xsl:call-template>
                    </xsl:element>
                    </td>
                  </tr>
                </xsl:for-each>
              </table>
              <br/>
            </xsl:if>
            <xsl:if test="count(basecompoundref) &gt; 0">
            <table class="memberdecls">
                <tr class="heading">
                  <td colspan="1">
                      <xsl:text>This module implements </xsl:text>
                <xsl:element name="a">
                  <xsl:attribute name="href">
                    <xsl:variable name="constructName" select="basecompoundref/@refid"/>
                    <xsl:value-of select="concat($constructName,'.html')"/>
                  </xsl:attribute>
                      <xsl:call-template name="string-replace-less-than">
                        <xsl:with-param name="text">
                          <xsl:call-template name="string-replace-greater-than">
                            <xsl:with-param name="text" select="basecompoundref"/>
                           </xsl:call-template>
                         </xsl:with-param>
                       </xsl:call-template>
                       </xsl:element>
                      <xsl:text> interface. </xsl:text>
                  </td>
                </tr>
              </table>
              <br/>
            </xsl:if>
            <xsl:if test="count(listofallmembers/member[normalize-space(name) != '']) &gt; 0">
              <table class="memberdecls">
                <tr class="heading">
                  <td colspan="1">
                    <h2 class="groupheader">
                      Methods
                    </h2>
                  </td>
                </tr>
                <xsl:for-each select="listofallmembers/member">
                  <tr class="memitem:">
                    <td class="memItemRight" valign="bottom">
                      <xsl:variable name="memberName" select="name"/>
                      <!-- <xsl:choose>
                        <xsl:when test="normalize-space(../../sectiondef/memberdef[name=$memberName]/detaileddescription) != ''"> -->
                          <xsl:element name="a">
                            <xsl:attribute name="href">
                              <xsl:value-of select="concat('#', $memberName)"/>
                            </xsl:attribute>
                            <xsl:value-of select="name"/>
                          </xsl:element>
                        <!--</xsl:when>
                        <xsl:otherwise>
                          <xsl:value-of select="name"/>
                        </xsl:otherwise>
                      </xsl:choose> -->
                    </td>
                  </tr>
                  <!-- </xsl:if> -->
                </xsl:for-each>
              </table>
              <h2 class="groupheader">Detailed Method Description</h2>
            <xsl:for-each select="sectiondef/memberdef">
                <xsl:variable name="memlno" select="location/@line"/>
                 <div class="memitem">
                  <div class="memproto">
                   <table class="mlabels">
                     <tr>
                        <td class="mlabels-left">
                          <table>
                            <xsl:element name="a">
                              <xsl:attribute name="id">
                                <xsl:value-of select="name"/>
                              </xsl:attribute>
                            </xsl:element>
                            <tr>
                            <td>
                              <xsl:call-template name="string-replace-less-than">
                                 <xsl:with-param name="text">
                                   <xsl:call-template name="string-replace-greater-than">
                                     <xsl:with-param name="text" select="type"/>
                                   </xsl:call-template>
                                 </xsl:with-param>
                              </xsl:call-template>
                          </td>
                          <td class="memname">
                          <b>
                            <a class="el">
                              <xsl:attribute name="href">
                                <xsl:value-of select="concat($htmlsourcefile, '#l', format-number($memlno, '00000'))"/>
                              </xsl:attribute>
                              <xsl:value-of select="name"/>
                            </a>
                          </b>
                          </td>
                          <td>
                          <xsl:text disable-output-escaping="yes"><![CDATA[(]]></xsl:text>
                          </td>
                          <xsl:for-each select="param">
                            <td class="paramtype">
                            <xsl:call-template name="string-replace-less-than">
                              <xsl:with-param name="text">
                                <xsl:call-template name="string-replace-greater-than">
                                  <xsl:with-param name="text" select="type"/>
                                </xsl:call-template>
                              </xsl:with-param>
                            </xsl:call-template>
                            </td>
                            <td class="paramname">
                            <xsl:value-of select="declname"/>
                            <xsl:if test="not(position() = last())">,</xsl:if>
                            </td>
                          </xsl:for-each>
                           <td>
                          <xsl:text disable-output-escaping="yes"><![CDATA[)]]></xsl:text>
                          </td>
                          </tr>
                          </table>
                        </td>
                      </tr>
                    </table>
                  </div>
                  <div class="memdoc">
                    <p>
                      <xsl:choose>
                        <xsl:when test="normalize-space(detaileddescription) != ''">
                          <xsl:value-of select="detaileddescription"/>
                          <br/> <br/>
                     </xsl:when>
                    </xsl:choose>
                        Definition at line 
                        <xsl:element name ="a">
                          <xsl:attribute name="href">
                          <xsl:value-of select="concat($htmlsourcefile, '#l', format-number($memlno, '00000'))"/>
                          </xsl:attribute>
                        <xsl:value-of select="$memlno"/>
                        </xsl:element>
                        of file 
                        <a class="el">
                        <xsl:attribute name="href">
                        <xsl:value-of select="$htmlsourcefile"/>
                        </xsl:attribute>
                        <xsl:value-of select="$sourcefile"/>
                        </a>
                    </p>
                  </div>
                </div>
            </xsl:for-each>
            </xsl:if>
            <hr/>
            The documentation for this class was generated from the following file:
            <ul>
              <li>
                <a class="el">
                  <xsl:attribute name="href">
                    <xsl:value-of select="$htmlsourcefile"/>
                  </xsl:attribute>
                  <xsl:value-of select="$sourcefile"/>
                </a>
              </li>
            </ul>
          </div>
          <!-- contents -->
        </div>
        <!-- doc-contents -->
      </body>
    </html>
  </xsl:template>
  <!-- Replace all < > in searchdata.xml  -->
  <xsl:template match="/add">
    <xsl:element name="add">
      <xsl:for-each select="doc">
        <xsl:element name="doc">
          <xsl:for-each select="field">
            <xsl:element name="field">
              <xsl:attribute name="name">
                <xsl:value-of select="@name"/>
              </xsl:attribute>
              <xsl:variable name="text">
                <xsl:choose>
                  <xsl:when test="@name='name'" >
                    <xsl:value-of select="substring(text(), 1, 200)"/>
                  </xsl:when>
                  <xsl:otherwise>
                    <xsl:value-of name="text" select="." />
                  </xsl:otherwise>
                </xsl:choose>
              </xsl:variable>
              <xsl:call-template name="string-replace-less-than">
                <xsl:with-param name="text">
                  <xsl:call-template name="string-replace-greater-than">
                    <xsl:with-param name="text" select="$text" />
                  </xsl:call-template>
                </xsl:with-param>
              </xsl:call-template>
            </xsl:element>
          </xsl:for-each>
        </xsl:element>
      </xsl:for-each>
    </xsl:element>
  </xsl:template>
  <!-- String replace function to replace < by #( -->
  <xsl:template name="string-replace-less-than">
    <xsl:param name="text"/>
    <xsl:variable name="replaceLessThan">
      <xsl:text disable-output-escaping="yes"><![CDATA[<]]></xsl:text>
    </xsl:variable>
    <xsl:variable name="byHashLeftParentheses">
      <xsl:text disable-output-escaping="yes"><![CDATA[#(]]></xsl:text>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="contains($text, $replaceLessThan)">
        <xsl:value-of select="substring-before($text,$replaceLessThan)"/>
        <xsl:value-of select="$byHashLeftParentheses"/>
        <xsl:call-template name="string-replace-less-than">
          <xsl:with-param name="text" select="substring-after($text,$replaceLessThan)"/>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$text"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <!-- String replace function to replace > by ) -->
  <xsl:template name="string-replace-greater-than">
    <xsl:param name="text"/>
    <xsl:variable name="replaceGreaterThan">
      <xsl:text disable-output-escaping="yes"><![CDATA[>]]></xsl:text>
    </xsl:variable>
    <xsl:variable name="byRightParentheses">
      <xsl:text disable-output-escaping="yes"><![CDATA[)]]></xsl:text>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="contains($text, $replaceGreaterThan)">
        <xsl:value-of select="substring-before($text,$replaceGreaterThan)"/>
        <xsl:value-of select="$byRightParentheses"/>
        <xsl:call-template name="string-replace-greater-than">
          <xsl:with-param name="text" select="substring-after($text,$replaceGreaterThan)"/>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$text"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <!-- template to extract filename from a given path -->
  <xsl:template name="getfilename">
    <xsl:param name="path"/>
    <xsl:choose>
      <xsl:when test="not(contains($path,'/'))">
        <xsl:value-of select="$path"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:call-template name="getfilename">
          <xsl:with-param name="path" select="substring-after($path, '/')"/>
        </xsl:call-template>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
</xsl:stylesheet>

